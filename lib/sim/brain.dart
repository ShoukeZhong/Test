import 'dart:math' as math;

import 'cat.dart';
import 'motor.dart';
import 'needs.dart';
import 'profile.dart';
import 'stimuli.dart';
import 'util.dart';

enum Act { rest, sleep, explore, groom, hunt, watch, startle, affection, petted, held, land }

const Map<Act, String> actLabel = {
  Act.rest: '休息',
  Act.sleep: '睡覺',
  Act.explore: '到處走走',
  Act.groom: '理毛',
  Act.hunt: '追手指',
  Act.watch: '盯著鏡頭外',
  Act.startle: '受到驚嚇',
  Act.affection: '來找你',
  Act.petted: '被摸',
  Act.held: '被抱著',
  Act.land: '落地',
};

class BrainCtx {
  BrainCtx(this.n, this.t, this.stim, this.loco, {this.carried = false, this.landImpact = -1});
  final Needs n;
  final Traits t;
  final Stimuli stim;
  final Locomotion loco;

  /// 被抱著或在空中（位置由物理決定，不會自己走）
  final bool carried;

  /// 這一幀剛落地時的撞擊速度（世界單位/秒）；沒落地是 -1
  final double landImpact;

  double get reach => CatBody.bodyLength * 0.62;
  double get walk => CatBody.walkSpeed;
  double get run => CatBody.runSpeed;
  double get minX => loco.minX;
  double get maxX => loco.maxX;
  double get midX => (loco.minX + loco.maxX) / 2;
}

/// 行為層：決定「現在想做什麼」，每幀輸出連續的運動意圖。
class Brain {
  Brain(this.rng);

  final math.Random rng;
  final MotorIntent intent = MotorIntent();
  Act act = Act.rest;
  double t = 0;
  int phase = 0;
  double phaseT = 0;
  double dur = 6;
  double tx = 50;
  int legs = 0;
  double overstim = 0;
  double nextLook = 0;
  double? lookX;
  double lookViewerUntil = 0;
  double nextMeow = 0;
  double motionQuiet = 0;
  double fingerGone = 0;
  double flinch = 0;
  Posture restPosture = Posture.sit;

  static double _pw(double x, double p) => math.pow(x, p).toDouble();

  bool get asleep => act == Act.sleep && phase == 1;

  /// 體力消耗（影響疲勞累積）
  double get load => switch (act) {
        Act.hunt || Act.startle || Act.held => 1.0,
        Act.explore => 0.3,
        _ => 0.0,
      };

  void update(double dt, BrainCtx c) {
    t += dt;
    phaseT += dt;
    flinch = math.max(0.0, flinch - dt);
    if (act != Act.petted) overstim = math.max(0.0, overstim - dt / 40);

    if (c.carried) {
      if (act != Act.held) {
        // 被抱起來：膽小的更怕，親人的比較不怕〔估〕
        c.n.fear = clampD(c.n.fear + 0.08 + 0.3 * c.t.fearfulness - 0.15 * c.t.sociability, 0, 1);
        _start(Act.held, c);
      }
      if (c.stim.loudOnset) c.n.fear = clampD(c.n.fear + 0.2 * c.t.fearfulness, 0, 1);
    } else if (c.landImpact >= 0) {
      // 撞擊越重越怕：約 300 單位/s（≈ 從 1.5 m 高落下）時 +0.4〔估〕
      c.n.fear = clampD(c.n.fear + clampD(c.landImpact / 300, 0, 1) * 0.4 * (0.5 + c.t.fearfulness), 0, 1);
      _start(Act.land, c);
    } else if (act == Act.held) {
      _start(Act.land, c); // 保險：不在手上也沒落地事件時，直接當作落地
    } else {
      _reactive(c);
    }

    intent.reset();
    switch (act) {
      case Act.rest:
        _rest(dt, c);
      case Act.sleep:
        _sleep(dt, c);
      case Act.explore:
        _explore(dt, c);
      case Act.groom:
        _groom(dt, c);
      case Act.hunt:
        _hunt(dt, c);
      case Act.watch:
        _watch(dt, c);
      case Act.startle:
        _startle(dt, c);
      case Act.affection:
        _affection(dt, c);
      case Act.petted:
        _petted(dt, c);
      case Act.held:
        _held(dt, c);
      case Act.land:
        _land(dt, c);
    }
    _post(c);
  }

  // ---------------- 反射：感官刺激可以打斷目前的行為 ----------------
  void _reactive(BrainCtx c) {
    final st = c.stim, n = c.n, t = c.t;
    final awake = !asleep;

    if (st.loudOnset) {
      n.fear = clampD(n.fear + 0.2 + 0.6 * t.fearfulness * clampD(st.soundLevel, 0.4, 1.0), 0, 1);
      flinch = 0.5;
      if (asleep && (st.soundLevel < 0.5 && rng.nextDouble() < 0.5)) {
        // 睡得熟，只動了動耳朵
      } else if (n.fear > 0.35 && act != Act.land) {
        _start(Act.startle, c);
        return;
      }
    }
    if (awake && st.motionBurst) {
      n.fear = clampD(n.fear + 0.15 * t.fearfulness, 0, 1);
      flinch = 0.4;
      if (n.fear > 0.5 && act != Act.land) {
        _start(Act.startle, c);
        return;
      }
    }
    if (st.strokeRegion != null && st.sinceStroke < 0.25 && act != Act.petted) {
      if (!(act == Act.startle && n.fear > 0.5)) {
        _start(Act.petted, c);
        return;
      }
    }
    if (st.poke && act != Act.petted) {
      n.fear = clampD(n.fear + 0.08 + 0.15 * t.fearfulness, 0, 1);
      flinch = 0.35;
      if (asleep) {
        _wake(c);
        return;
      }
    }
    if (!awake) return;
    const busy = {Act.startle, Act.petted, Act.land};
    if (busy.contains(act)) return;

    const idle = {Act.rest, Act.explore, Act.groom, Act.watch, Act.affection};
    if (st.fingerX != null && act != Act.hunt && idle.contains(act) && n.boredom > 0.05 && n.fatigue < 0.85) {
      _start(Act.hunt, c);
      return;
    }
    if (st.cameraOn && st.motion > 0.08 && (act == Act.rest || act == Act.explore || act == Act.groom)) {
      if (rng.nextDouble() < 0.02 + 0.03 * t.impulsiveness) {
        _start(Act.watch, c);
        return;
      }
    }
    if (st.voiceSeconds > 0.6 && (act == Act.rest || act == Act.explore || act == Act.groom)) {
      if (rng.nextDouble() < 0.01 + 0.04 * t.sociability) {
        _start(Act.affection, c);
        return;
      }
    }
  }

  // ---------------- 選擇下一個行為（效用 + softmax 隨機） ----------------
  void _choose(BrainCtx c) {
    final n = c.n, t = c.t;
    final u = <Act, double>{
      Act.rest: 0.14,
      Act.sleep: _pw(n.fatigue, 1.6) * (1.4 - 0.6 * t.activity),
      Act.explore: n.boredom * (0.2 + 0.7 * t.impulsiveness) * (1 - 0.5 * n.fatigue) + 0.04,
      Act.affection: n.loneliness * (0.15 + 1.0 * t.sociability),
      Act.groom: 0.06 + 0.1 * (1 - t.activity) + 0.3 * n.fear * (1 - t.fearfulness),
    };
    final keys = u.keys.where((k) => u[k]! > 0).toList();
    final temp = 0.06 + 0.10 * t.impulsiveness;
    var maxU = 0.0;
    for (final k in keys) {
      if (u[k]! > maxU) maxU = u[k]!;
    }
    final wts = keys.map((k) => math.exp((u[k]! - maxU) / temp)).toList();
    final sum = wts.reduce((a, b) => a + b);
    var r = rng.nextDouble() * sum;
    var pick = keys.last;
    for (var i = 0; i < keys.length; i++) {
      r -= wts[i];
      if (r <= 0) {
        pick = keys[i];
        break;
      }
    }
    _start(pick, c);
  }

  void _start(Act a, BrainCtx c) {
    act = a;
    t = 0;
    phase = 0;
    phaseT = 0;
    final n = c.n;
    switch (a) {
      case Act.rest:
        dur = (6 + rng.nextDouble() * 22) * (0.6 + 0.8 * (1 - c.t.activity));
        if (n.fatigue > 0.55) {
          restPosture = rng.nextBool() ? Posture.loaf : Posture.lie;
        } else {
          restPosture = const [Posture.sit, Posture.sit, Posture.loaf, Posture.stand][rng.nextInt(4)];
        }
      case Act.explore:
        legs = 1 + rng.nextInt(3);
        tx = _randomX(c);
      case Act.groom:
        dur = 6 + rng.nextDouble() * 9;
      case Act.affection:
        tx = c.midX + (rng.nextDouble() - 0.5) * (c.maxX - c.minX) * 0.3;
        dur = 8 + rng.nextDouble() * 8;
        nextMeow = 0.6;
      case Act.startle:
        tx = c.loco.x < c.midX ? c.maxX - 3 : c.minX + 3;
      case Act.sleep:
        // 走到比較近的螢幕邊緣再睡：不擋住畫面中間〔設計選擇〕
        tx = c.loco.x < c.midX ? c.minX + 2 : c.maxX - 2;
      case Act.held:
        nextMeow = 0.8;
      default:
        break;
    }
    petLog('act=${a.name}');
  }

  void _wake(BrainCtx c) {
    if (act == Act.sleep) {
      phase = 2;
      phaseT = 0;
      petLog('act=wake');
    }
  }

  double _randomX(BrainCtx c) {
    final span = c.maxX - c.minX;
    for (var i = 0; i < 6; i++) {
      final x = c.minX + rng.nextDouble() * span;
      if ((x - c.loco.x).abs() > math.min(12.0, span * 0.3)) return x;
    }
    return c.midX;
  }

  bool _walkTo(BrainCtx c, double x, double speed) {
    intent.targetX = x;
    intent.speed = speed;
    return c.loco.arrived(clampD(x, c.minX, c.maxX));
  }

  void _lookAround(double dt, BrainCtx c) {
    nextLook -= dt;
    if (nextLook <= 0) {
      nextLook = 1.5 + rng.nextDouble() * 4;
      if (rng.nextDouble() < 0.12 + 0.25 * c.t.sociability) {
        lookViewerUntil = t + 1 + rng.nextDouble() * 2;
        lookX = null;
      } else {
        lookX = c.minX + rng.nextDouble() * (c.maxX - c.minX);
      }
    }
    if (t < lookViewerUntil) intent.lookAtViewer = 1;
    intent.gazeX = lookX;
  }

  // ---------------- 各行為 ----------------
  void _rest(double dt, BrainCtx c) {
    intent.posture = restPosture;
    intent.tailUp = 0.1;
    _lookAround(dt, c);
    if (t > dur) _choose(c);
  }

  void _sleep(double dt, BrainCtx c) {
    switch (phase) {
      case 0:
        if (_walkTo(c, tx, c.walk * 0.6) || t > 25) {
          phase = 1;
          phaseT = 0;
        }
      case 1:
        intent.posture = c.n.fatigue < 0.3 ? Posture.lie : Posture.curl;
        intent.eyes = 0;
        intent.breath = 0.75;
        intent.tailUp = -0.6;
        if (c.n.fatigue < 0.06) {
          phase = 2;
          phaseT = 0;
        }
      case 2: // 醒來：睜眼、打哈欠
        intent.posture = Posture.loaf;
        intent.eyes = clampD(phaseT / 1.2, 0, 1);
        intent.mouth = phaseT > 0.4 && phaseT < 1.1 ? 1 : 0;
        if (phaseT > 1.4) {
          phase = 3;
          phaseT = 0;
        }
      default: // 伸懶腰
        intent.posture = Posture.stretch;
        if (phaseT > 1.8) _choose(c);
    }
  }

  void _explore(double dt, BrainCtx c) {
    c.n.boredom = math.max(0.0, c.n.boredom - dt * 0.004);
    if (phase == 0) {
      if (_walkTo(c, tx, c.walk * 0.75) || t > 30) {
        phase = 1;
        phaseT = 0;
        dur = 1 + rng.nextDouble() * 2.5;
      }
    } else {
      intent.posture = Posture.dip;
      intent.headDip = 0.85; // 聞一聞
      if (phaseT > dur) {
        legs--;
        if (legs <= 0) {
          _choose(c);
        } else {
          tx = _randomX(c);
          phase = 0;
          t = 0;
        }
      }
    }
  }

  void _groom(double dt, BrainCtx c) {
    intent.posture = Posture.sit;
    final cyc = (t % 3.2) / 3.2;
    intent.pawLift = cyc < 0.5 ? 0.8 : 1;
    intent.headDip = cyc < 0.5 ? 0.35 : 0.1;
    intent.headTilt = cyc < 0.5 ? 0 : 0.5;
    intent.mouth = cyc < 0.5 ? 0.25 * (0.5 + 0.5 * math.sin(t * 14)) : 0;
    intent.eyes = 0.5;
    c.n.fear = math.max(0.0, c.n.fear - dt * 0.02);
    if (t > dur) _choose(c);
  }

  void _hunt(double dt, BrainCtx c) {
    final fx = c.stim.fingerX;
    if (fx == null) {
      fingerGone += dt;
      intent.posture = Posture.crouch;
      if (fingerGone > 0.8) _choose(c);
      return;
    }
    fingerGone = 0;
    c.n.boredom = math.max(0.0, c.n.boredom - dt * 0.02);
    final dir = fx >= c.loco.x ? 1.0 : -1.0;
    intent.gazeX = fx;
    intent.gazeY = c.stim.fingerY;
    intent.tailLash = 0.4;
    switch (phase) {
      case 0: // 潛行接近
        intent.posture = Posture.crouch;
        _walkTo(c, fx - dir * c.reach * 1.5, c.walk * 0.45);
        if ((c.loco.x - (fx - dir * c.reach * 1.5)).abs() < 3 && c.stim.fingerSpeed < 40) {
          phase = 1;
          phaseT = 0;
          dur = 0.6 + rng.nextDouble() * 0.9;
        }
      case 1: // 扭屁股
        intent.posture = Posture.crouch;
        intent.wiggle = 1;
        intent.faceDir = dir;
        if (phaseT > dur) {
          phase = 2;
          phaseT = 0;
        }
      default: // 撲
        intent.posture = Posture.stand;
        intent.pawLift = 1;
        _walkTo(c, fx - dir * c.reach * 0.45, c.run);
        if (phaseT > 0.6) {
          phase = 0;
          phaseT = 0;
          petLog('pounce');
        }
    }
  }

  void _watch(double dt, BrainCtx c) {
    final st = c.stim;
    final gx = c.minX + st.motionX * (c.maxX - c.minX);
    intent.lookAtViewer = 1;
    intent.gazeX = gx;
    intent.gazeY = 8;
    intent.posture = Posture.sit;
    intent.tailLash = clampD(st.motion * 2, 0, 0.6);
    if (st.motion > 0.2 && c.n.boredom > 0.25) {
      intent.posture = Posture.stand;
      if (_walkTo(c, gx, c.walk * 0.8)) {
        intent.pawLift = 0.5 + 0.5 * math.sin(t * 9).abs();
      }
    }
    motionQuiet = st.motion < 0.04 ? motionQuiet + dt : 0;
    if (motionQuiet > 2.5 || t > 30) _choose(c);
  }

  void _startle(double dt, BrainCtx c) {
    intent.earsBack = 1;
    intent.tailPuff = clampD(c.n.fear * 1.5, 0, 1);
    switch (phase) {
      case 0:
        intent.posture = Posture.crouch;
        if (phaseT > 0.35) {
          phase = c.n.fear > 0.45 ? 1 : 2;
          phaseT = 0;
        }
      case 1:
        intent.posture = Posture.crouch;
        if (_walkTo(c, tx, c.run) || phaseT > 6) {
          phase = 2;
          phaseT = 0;
        }
      default:
        intent.posture = phaseT < 3 ? Posture.crouch : Posture.loaf;
        intent.faceDir = c.loco.x < c.midX ? 1.0 : -1.0;
        intent.lookAtViewer = 0.6;
        if (c.n.fear < 0.15 || phaseT > 20) _choose(c);
    }
  }

  void _affection(double dt, BrainCtx c) {
    if (phase == 0) {
      intent.tailUp = 1;
      if (_walkTo(c, tx, c.walk) || t > 15) {
        phase = 1;
        phaseT = 0;
      }
      return;
    }
    intent.posture = Posture.sit;
    intent.lookAtViewer = 1;
    intent.tailUp = 0.8;
    c.n.loneliness = math.max(0.0, c.n.loneliness - dt * 0.004);
    final cyc = phaseT % 3.5; // 慢眨眼
    intent.eyes = cyc > 2.6 && cyc < 3.3 ? 0.15 : 1;
    nextMeow -= dt;
    if (nextMeow <= 0 && nextMeow > -0.5) intent.mouth = 0.8;
    if (nextMeow <= -0.5) nextMeow = 6 + rng.nextDouble() * 6;
    if (phaseT > dur) _choose(c);
  }

  static const Map<BodyRegion, double> _catLike = {
    BodyRegion.cheek: 1.0,
    BodyRegion.head: 0.9,
    BodyRegion.back: 0.6,
    BodyRegion.belly: 0.1,
    BodyRegion.tail: 0.0,
    BodyRegion.legs: 0.2,
  };

  void _petted(double dt, BrainCtx c) {
    final st = c.stim;
    if (st.sinceStroke > 1.2) {
      _choose(c);
      return;
    }
    final region = st.strokeRegion ?? BodyRegion.back;
    final like = _catLike[region]!;
    final sp = st.strokeSpeed;
    final speedOk = sp < 4 ? 0.6 : (sp < 70 ? 1.0 : clampD(1 - (sp - 70) / 80, 0, 1));
    final pleasure = like * (0.5 + c.t.sociability) * speedOk - c.n.fear * 0.8;
    final tol = 15 + 50 * c.t.sociability;
    overstim += dt / tol * (region == BodyRegion.belly ? 3 : 1);
    intent.posture = Posture.loaf;
    intent.gazeX = null;

    if (pleasure > 0.35 && overstim < 0.75) {
      intent.purr = true;
      intent.eyes = 0.35;
      intent.lookAtViewer = 0.35;
      intent.headTilt = region == BodyRegion.cheek || region == BodyRegion.head ? 0.6 : 0.2;
      intent.tailUp = 0.7;
      intent.knead = c.t.sociability > 0.6 ? 0.6 : 0;
      c.n.loneliness = math.max(0.0, c.n.loneliness - dt * 0.02);
      c.n.fear = math.max(0.0, c.n.fear - dt * 0.03);
    } else if (overstim < 1 && pleasure > 0.08) {
      intent.tailLash = 0.7; // 警告：尾巴開始甩
      intent.earsBack = 0.5;
      intent.eyes = 0.8;
    } else {
      intent.earsBack = 1;
      intent.pawLift = 1;
      if (phase != 9) {
        phase = 9;
        phaseT = 0;
        petLog('swat (pleasure=${pleasure.toStringAsFixed(2)} overstim=${overstim.toStringAsFixed(2)})');
      }
      if (phaseT > 0.35) {
        c.n.fear = clampD(c.n.fear + 0.05, 0, 1);
        _start(Act.explore, c);
      }
    }
  }

  /// 被抱著（以及被放開後在空中）：親人的貓放鬆，膽小／獨立的貓掙扎、叫。
  void _held(double dt, BrainCtx c) {
    final n = c.n, tr = c.t;
    // 抱太久，不親人的貓越來越不耐煩〔估〕
    n.fear = clampD(n.fear + dt * 0.012 * (1 - tr.sociability), 0, 1);
    final calm = clampD(tr.sociability * 1.2 - n.fear * 1.5, 0, 1);
    intent.posture = Posture.stand;
    intent.struggle = clampD(n.fear * 1.3 + (0.5 - tr.sociability) * 0.8 - 0.1, 0, 1);
    intent.earsBack = clampD(n.fear * 1.2, 0, 1);
    intent.tailPuff = n.fear > 0.55 ? clampD((n.fear - 0.55) * 2.2, 0, 1) : 0;
    intent.tailLash = intent.struggle * 0.8;
    intent.eyes = calm > 0.6 ? 0.7 : 1;
    intent.lookAtViewer = 0.7;
    intent.purr = calm > 0.75 && n.fear < 0.1;
    nextMeow -= dt;
    if (intent.struggle > 0.35 && nextMeow <= 0) {
      intent.mouth = 0.85;
      if (nextMeow < -0.5) {
        nextMeow = 2 + rng.nextDouble() * 3;
        petLog('meow (held, struggle=${intent.struggle.toStringAsFixed(2)})');
      }
    }
  }

  /// 落地：先蹲低吸收衝擊，再決定逃開、理毛（安撫自己），或照常
  void _land(double dt, BrainCtx c) {
    intent.posture = Posture.crouch;
    intent.earsBack = clampD(c.n.fear * 1.2, 0, 1);
    intent.tailPuff = c.n.fear > 0.6 ? 0.5 : 0;
    if (phaseT < 0.35) return;
    if (c.n.fear > 0.45) {
      _start(Act.startle, c);
      phase = 1; // 直接跑開
    } else if (rng.nextDouble() < 0.35 + 0.3 * (1 - c.t.sociability)) {
      _start(Act.groom, c); // 被搬動後理毛很常見〔記憶〕
    } else {
      _choose(c);
    }
  }

  // ---------------- 統一後處理 ----------------
  void _post(BrainCtx c) {
    if (flinch > 0) {
      intent.earsBack = math.max(intent.earsBack, 0.8);
      intent.eyes = math.min(1, intent.eyes + 0.3);
    }
    if (c.n.fear > 0.3) intent.earsBack = math.max(intent.earsBack, c.n.fear);
  }
}
