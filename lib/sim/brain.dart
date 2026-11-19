import 'dart:math' as math;

import 'life.dart';
import 'motor.dart';
import 'physiology.dart';
import 'profile.dart';
import 'species.dart';
import 'state.dart';
import 'stimuli.dart';
import 'util.dart';
import 'world.dart';

enum Act { rest, sleep, explore, eat, drink, toilet, groom, play, hunt, watch, startle, affection, petted, nurse, askFood, askWater, dying, dead }

const Map<Act, String> actLabel = {
  Act.rest: '休息',
  Act.sleep: '睡覺',
  Act.explore: '探索',
  Act.eat: '吃飯',
  Act.drink: '喝水',
  Act.toilet: '上廁所',
  Act.groom: '理毛',
  Act.play: '玩球',
  Act.hunt: '追手指',
  Act.watch: '盯著鏡頭外',
  Act.startle: '受到驚嚇',
  Act.affection: '來找你',
  Act.petted: '被摸',
  Act.nurse: '窩在媽媽身邊',
  Act.askFood: '討飯',
  Act.askWater: '討水',
  Act.dying: '虛弱',
  Act.dead: '離世',
};

class BrainCtx {
  BrainCtx(this.s, this.w, this.stim, this.loco, this.life, this.nowMs);
  final PetState s;
  final World w;
  final Stimuli stim;
  final Locomotion loco;
  final LifeInfo life;
  final int nowMs;
  SpeciesInfo get sp => s.info;
  Traits get t => s.traits;
  Needs get n => s.needs;
  double get size => life.growth;
  double get reach => sp.bodyLength * life.growth * 0.62;
  double get walk => sp.walkSpeed * (0.45 + 0.55 * life.growth);
  double get run => sp.runSpeed * (0.45 + 0.55 * life.growth) * (1 - 0.4 * life.endOfLife);
  bool get isCat => s.species == Species.cat;
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
  WasteKind toiletKind = WasteKind.urine;
  bool toiletRefused = false;
  double overstim = 0;
  double nextLook = 0;
  double? lookX;
  double lookViewerUntil = 0;
  double nextMeow = 0;
  double batCooldown = 0;
  double motionQuiet = 0;
  double fingerGone = 0;
  double flinch = 0;
  Posture restPosture = Posture.sit;
  double side = 1;

  static double _pw(double x, double p) => math.pow(x, p).toDouble();

  bool get asleep =>
      (act == Act.sleep && phase == 1) || (act == Act.nurse && phase == 1) || (act == Act.dying && phase == 1) || act == Act.dead;

  /// 體力消耗（影響疲勞累積）
  double get load => switch (act) {
        Act.play || Act.hunt || Act.startle => 1.0,
        Act.explore => 0.3,
        _ => 0.0,
      };

  void update(double dt, BrainCtx c) {
    t += dt;
    phaseT += dt;
    batCooldown = math.max(0.0, batCooldown - dt);
    flinch = math.max(0.0, flinch - dt);
    if (act != Act.petted) overstim = math.max(0.0, overstim - dt / 40);

    if (c.s.dead) {
      if (act != Act.dead) _start(Act.dead, c);
    } else {
      if (act != Act.dying && (c.life.endOfLife > 0.85 || c.s.health < 0.12)) _start(Act.dying, c);
      if (act != Act.dying) _reactive(c);
    }

    intent.reset();
    switch (act) {
      case Act.rest:
        _rest(dt, c);
      case Act.sleep:
        _sleep(dt, c);
      case Act.explore:
        _explore(dt, c);
      case Act.eat:
        _eat(dt, c);
      case Act.drink:
        _drink(dt, c);
      case Act.toilet:
        _toilet(dt, c);
      case Act.groom:
        _groom(dt, c);
      case Act.play:
        _play(dt, c);
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
      case Act.nurse:
        _nurse(dt, c);
      case Act.askFood:
        _ask(dt, c, food: true);
      case Act.askWater:
        _ask(dt, c, food: false);
      case Act.dying:
        _dying(dt, c);
      case Act.dead:
        _dead(c);
    }
    _post(c);
  }

  // ---------------- 反射：感官刺激可以打斷目前的行為 ----------------
  void _reactive(BrainCtx c) {
    final st = c.stim, life = c.life, n = c.n, t = c.t;
    final awake = !asleep;

    if (life.canHear && st.loudOnset) {
      n.fear = clampD(n.fear + 0.2 + 0.6 * t.fearfulness * clampD(st.soundLevel, 0.4, 1.0), 0, 1);
      flinch = 0.5;
      if (asleep && (st.soundLevel < 0.5 && rng.nextDouble() < 0.5)) {
        // 睡得熟，只動了動耳朵
      } else if (n.fear > 0.35 && life.mobility > 0.3) {
        _start(Act.startle, c);
        return;
      }
    }
    if (life.canSee && awake && st.motionBurst) {
      n.fear = clampD(n.fear + 0.15 * t.fearfulness, 0, 1);
      flinch = 0.4;
      if (n.fear > 0.5 && life.mobility > 0.3) {
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
    const busy = {Act.eat, Act.drink, Act.toilet, Act.startle, Act.petted, Act.askFood, Act.askWater};
    if (busy.contains(act)) return;

    // 急著上廁所
    if (life.usesToilet && (n.bladder >= 0.97 || n.bowel >= 0.97)) {
      _start(Act.toilet, c);
      return;
    }
    const idle = {Act.rest, Act.explore, Act.groom, Act.watch, Act.affection, Act.play};
    if (st.fingerX != null && act != Act.hunt && idle.contains(act) && life.mobility > 0.5 && n.boredom > 0.1 && n.fatigue < 0.85) {
      _start(Act.hunt, c);
      return;
    }
    if (c.w.ball.moving && act != Act.play && act != Act.hunt && idle.contains(act) && life.mobility > 0.5 && n.boredom > 0.15) {
      _start(Act.play, c);
      return;
    }
    if (st.cameraOn && life.canSee && st.motion > 0.08 && (act == Act.rest || act == Act.explore || act == Act.groom)) {
      if (rng.nextDouble() < 0.02 + 0.03 * t.impulsiveness) {
        _start(Act.watch, c);
        return;
      }
    }
    if (life.canHear && st.voiceSeconds > 0.6 && (act == Act.rest || act == Act.explore || act == Act.groom)) {
      if (rng.nextDouble() < 0.01 + 0.04 * t.sociability) {
        _start(Act.affection, c);
        return;
      }
    }
  }

  // ---------------- 選擇下一個行為（效用 + softmax 隨機） ----------------
  void _choose(BrainCtx c) {
    final life = c.life, n = c.n, t = c.t, w = c.w;
    final u = <Act, double>{};
    final days = life.days;
    final canWalk = days >= c.sp.walkDay;
    final weaned = life.weaning;

    u[Act.rest] = 0.14;
    if (life.motherPresent && days < c.sp.weanEndDay) {
      u[Act.nurse] = (life.motherCares ? 0.6 : 0.3 * (1 - weaned)) + n.fatigue * 0.6;
    }
    if (!life.motherCares) u[Act.sleep] = _pw(n.fatigue, 1.6) * (1.4 - 0.6 * t.activity) + 0.3 * life.endOfLife;
    u[Act.explore] = (n.boredom * (0.2 + 0.7 * t.impulsiveness) * (1 - 0.5 * n.fatigue) + 0.04) * (canWalk ? 1 : 0.5);
    if (canWalk) {
      u[Act.play] = n.boredom * (0.3 + 0.9 * t.activity) * (1 + life.youth) * (1 - n.fatigue);
      u[Act.affection] = n.loneliness * (0.15 + 1.0 * t.sociability);
    }
    if (weaned > 0) {
      if (w.food > 0.01) u[Act.eat] = _pw(n.hunger, 1.3) * (0.6 + 0.9 * t.appetite) * (0.3 + 0.7 * weaned);
      if (w.water > 0.01) u[Act.drink] = _pw(n.thirst, 1.3) * 1.1;
      if (weaned > 0.5 && w.food <= 0.01 && n.hunger > 0.5) u[Act.askFood] = n.hunger * 0.9;
      if (weaned > 0.5 && w.water <= 0.01 && n.thirst > 0.5) u[Act.askWater] = n.thirst * 0.95;
    }
    final elim = math.max(n.bladder, n.bowel);
    if (life.usesToilet && elim > 0.55) u[Act.toilet] = _pw(elim, 2.2) * 1.6;
    if (days > 42) u[Act.groom] = 0.06 + 0.1 * (1 - t.activity) + 0.3 * n.fear * (1 - t.fearfulness);

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
        if (c.life.days < c.sp.walkDay) {
          restPosture = Posture.lie;
        } else if (n.fatigue > 0.55) {
          restPosture = rng.nextBool() ? Posture.loaf : Posture.lie;
        } else {
          restPosture = const [Posture.sit, Posture.sit, Posture.loaf, Posture.stand][rng.nextInt(4)];
        }
      case Act.explore:
        legs = 1 + rng.nextInt(3);
        tx = _randomX(c);
      case Act.eat:
        side = c.loco.x >= World.foodX ? 1 : -1;
        tx = World.foodX + side * c.reach;
      case Act.drink:
        side = c.loco.x >= World.waterX ? 1 : -1;
        tx = World.waterX + side * c.reach;
      case Act.askFood:
        side = c.loco.x >= World.foodX ? 1 : -1;
        tx = World.foodX + side * c.reach * 1.3;
        nextMeow = 0.5;
      case Act.askWater:
        side = c.loco.x >= World.waterX ? 1 : -1;
        tx = World.waterX + side * c.reach * 1.3;
        nextMeow = 0.5;
      case Act.toilet:
        toiletKind = n.bladder >= n.bowel ? WasteKind.urine : WasteKind.feces;
        toiletRefused = c.w.toilet.length >= World.toiletRefuseCount;
        tx = World.toiletX + (rng.nextDouble() - 0.5) * 4;
      case Act.groom:
        dur = 6 + rng.nextDouble() * 9;
      case Act.play:
        dur = 10 + rng.nextDouble() * 15;
      case Act.affection:
        tx = 50 + (rng.nextDouble() - 0.5) * 20;
        dur = 8 + rng.nextDouble() * 8;
        nextMeow = 0.6;
      case Act.startle:
        tx = c.loco.x < 50 ? World.maxX - 3 : World.minX + 3;
      case Act.sleep:
        tx = World.bedX;
      case Act.nurse:
        tx = World.nestX + 4;
        dur = 20 + rng.nextDouble() * 40;
      case Act.dying:
        tx = c.life.motherPresent ? World.nestX : World.bedX;
      default:
        break;
    }
    petLog('act=${a.name}');
  }

  void _wake(BrainCtx c) {
    if (act == Act.sleep || act == Act.nurse) {
      act = Act.sleep;
      phase = 2;
      phaseT = 0;
      petLog('act=wake');
    }
  }

  double _randomX(BrainCtx c) {
    for (var i = 0; i < 6; i++) {
      final x = World.minX + 6 + rng.nextDouble() * (World.maxX - World.minX - 12);
      if ((x - c.loco.x).abs() > 12) return x;
    }
    return 50;
  }

  bool _walkTo(BrainCtx c, double x, double speed) {
    intent.targetX = x;
    intent.speed = speed;
    return c.loco.arrived(x);
  }

  void _lookAround(double dt, BrainCtx c) {
    nextLook -= dt;
    if (nextLook <= 0) {
      nextLook = 1.5 + rng.nextDouble() * 4;
      if (rng.nextDouble() < 0.12 + 0.25 * c.t.sociability) {
        lookViewerUntil = t + 1 + rng.nextDouble() * 2;
        lookX = null;
      } else {
        lookX = World.minX + rng.nextDouble() * (World.maxX - World.minX);
      }
    }
    if (t < lookViewerUntil) intent.lookAtViewer = 1;
    intent.gazeX = lookX;
  }

  // ---------------- 各行為 ----------------
  void _rest(double dt, BrainCtx c) {
    intent.posture = restPosture;
    intent.tailUp = c.isCat ? 0.1 : 0;
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
    final crawling = c.life.days < c.sp.walkDay;
    if (phase == 0) {
      final target = crawling ? clampD(tx, World.nestX - 10, World.nestX + 10) : tx;
      if (_walkTo(c, target, c.walk * (crawling ? 0.25 : 0.75)) || t > 30) {
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

  void _eat(double dt, BrainCtx c) {
    if (phase == 0) {
      if (_walkTo(c, tx, c.walk) || t > 20) {
        phase = 1;
        phaseT = 0;
      }
      return;
    }
    intent.faceDir = -side;
    intent.posture = Posture.dip;
    intent.headDip = 1;
    intent.chew = 1;
    Physiology.eat(c.s, c.w, 0.012 * dt);
    if (c.w.food <= 0.001 && c.n.hunger > 0.35) {
      _start(Act.askFood, c);
    } else if (c.n.hunger < 0.08 || c.w.food <= 0.001 || phaseT > 90) {
      _choose(c);
    }
  }

  void _drink(double dt, BrainCtx c) {
    if (phase == 0) {
      if (_walkTo(c, tx, c.walk) || t > 20) {
        phase = 1;
        phaseT = 0;
      }
      return;
    }
    intent.faceDir = -side;
    intent.posture = Posture.dip;
    intent.headDip = 1;
    intent.lap = 1;
    Physiology.drink(c.s, c.w, 0.015 * dt);
    if (c.w.water <= 0.001 && c.n.thirst > 0.35) {
      _start(Act.askWater, c);
    } else if (c.n.thirst < 0.06 || c.w.water <= 0.001 || phaseT > 60) {
      _choose(c);
    }
  }

  void _toilet(double dt, BrainCtx c) {
    final cat = c.isCat;
    switch (phase) {
      case 0:
        if (_walkTo(c, tx, c.walk * 1.1) || t > 20) {
          phase = toiletRefused ? 10 : (cat ? 1 : 2);
          phaseT = 0;
        }
      case 1: // 撥砂
        intent.dig = 1;
        intent.headDip = 0.6;
        if (phaseT > 1.8) {
          phase = 2;
          phaseT = 0;
        }
      case 2: // 蹲下
        intent.posture = Posture.squat;
        intent.tailUp = 0.4;
        intent.eyes = 0.6;
        final need = toiletKind == WasteKind.urine ? 8.0 : 14.0;
        if (phaseT > need) {
          Physiology.eliminate(c.s, c.w, toiletKind, c.loco.x, inToilet: true);
          petLog('toilet ${toiletKind.name} in box (${c.w.toilet.length})');
          phase = cat ? 3 : 4;
          phaseT = 0;
        }
      case 3: // 埋起來
        intent.dig = 1;
        intent.headDip = 0.5;
        if (phaseT > 2.5) {
          phase = 4;
          phaseT = 0;
        }
      case 4:
        if (_walkTo(c, World.toiletX + 22, c.walk) || phaseT > 8) _choose(c);
      case 10: // 太髒，聞一聞不想用
        intent.posture = Posture.dip;
        intent.headDip = 0.8;
        intent.earsBack = 0.3;
        if (phaseT > 2) {
          tx = World.toiletX + 30 + rng.nextDouble() * 45;
          phase = 11;
          phaseT = 0;
        }
      case 11:
        if (_walkTo(c, tx, c.walk) || phaseT > 15) {
          phase = 12;
          phaseT = 0;
        }
      default:
        intent.posture = Posture.squat;
        intent.tailUp = 0.3;
        if (phaseT > 8) {
          Physiology.eliminate(c.s, c.w, toiletKind, c.loco.x, inToilet: false);
          petLog('toilet ${toiletKind.name} ACCIDENT on floor');
          _choose(c);
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

  void _play(double dt, BrainCtx c) {
    final b = c.w.ball;
    c.n.boredom = math.max(0.0, c.n.boredom - dt * 0.01);
    if (b.held) {
      intent.posture = Posture.crouch;
      intent.lookAtViewer = 0.6;
      intent.wiggle = 0.5;
      if (t > dur) _choose(c);
      return;
    }
    final dir = b.x >= c.loco.x ? 1.0 : -1.0;
    final standX = b.x - dir * c.reach * 0.75;
    intent.gazeX = b.x;
    intent.gazeY = b.y;
    final near = (c.loco.x - standX).abs() < 2.5;
    _walkTo(c, standX, b.moving ? c.run : c.walk * 1.2);
    intent.posture = near ? Posture.crouch : Posture.stand;
    if (near && b.y < 4 && batCooldown <= 0) {
      batCooldown = 0.9 + rng.nextDouble() * 0.8;
      b.vx = dir * (20 + rng.nextDouble() * 40);
      b.vy = 15 + rng.nextDouble() * 25;
      c.n.boredom = math.max(0.0, c.n.boredom - 0.06);
      petLog('bat ball');
    }
    if (batCooldown > 0.5) intent.pawLift = 1;
    if (t > dur || c.n.boredom < 0.05 || c.n.fatigue > 0.88) _choose(c);
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
    intent.gazeY = 0.5;
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
    final gx = World.minX + st.motionX * (World.maxX - World.minX);
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
        intent.faceDir = c.loco.x < 50 ? 1.0 : -1.0;
        intent.lookAtViewer = 0.6;
        if (c.n.fear < 0.15 || phaseT > 20) _choose(c);
    }
  }

  void _affection(double dt, BrainCtx c) {
    if (phase == 0) {
      intent.tailUp = c.isCat ? 1 : 0.4;
      intent.tailWag = c.isCat ? 0 : 1;
      if (_walkTo(c, tx, c.walk) || t > 15) {
        phase = 1;
        phaseT = 0;
      }
      return;
    }
    intent.posture = Posture.sit;
    intent.lookAtViewer = 1;
    intent.tailUp = c.isCat ? 0.8 : 0.3;
    intent.tailWag = c.isCat ? 0 : 0.8;
    c.n.loneliness = math.max(0.0, c.n.loneliness - dt * 0.004);
    if (c.isCat) {
      final cyc = phaseT % 3.5; // 慢眨眼
      intent.eyes = cyc > 2.6 && cyc < 3.3 ? 0.15 : 1;
    } else {
      intent.mouth = 0.35;
    }
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
  static const Map<BodyRegion, double> _dogLike = {
    BodyRegion.cheek: 0.8,
    BodyRegion.head: 0.8,
    BodyRegion.back: 0.8,
    BodyRegion.belly: 0.9,
    BodyRegion.tail: 0.2,
    BodyRegion.legs: 0.3,
  };

  void _petted(double dt, BrainCtx c) {
    final st = c.stim;
    if (st.sinceStroke > 1.2) {
      _choose(c);
      return;
    }
    final region = st.strokeRegion ?? BodyRegion.back;
    final like = (c.isCat ? _catLike : _dogLike)[region]!;
    final sp = st.strokeSpeed;
    final speedOk = sp < 4 ? 0.6 : (sp < 70 ? 1.0 : clampD(1 - (sp - 70) / 80, 0, 1));
    final pleasure = like * (0.5 + c.t.sociability) * speedOk - c.n.fear * 0.8;
    final tol = c.isCat ? 15 + 50 * c.t.sociability : 60 + 60 * c.t.sociability;
    overstim += dt / tol * (c.isCat && region == BodyRegion.belly ? 3 : 1);
    intent.posture = phase == 0 ? (c.life.days < c.sp.walkDay ? Posture.lie : Posture.loaf) : Posture.loaf;
    intent.gazeX = null;

    if (pleasure > 0.35 && overstim < 0.75) {
      intent.purr = true;
      intent.eyes = 0.35;
      intent.lookAtViewer = 0.35;
      intent.headTilt = region == BodyRegion.cheek || region == BodyRegion.head ? 0.6 : 0.2;
      intent.tailUp = c.isCat ? 0.7 : 0.2;
      intent.tailWag = c.isCat ? 0 : 1;
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

  void _nurse(double dt, BrainCtx c) {
    intent.faceDir = -1.0;
    if (phase == 0) {
      if (_walkTo(c, tx, c.walk * 0.3) || t > 20) {
        phase = 1;
        phaseT = 0;
      }
      return;
    }
    intent.posture = c.n.fatigue > 0.2 ? Posture.curl : Posture.lie;
    final suckling = c.n.hunger > 0.25;
    intent.knead = suckling ? 0.8 : 0;
    intent.eyes = suckling ? 0.5 : 0;
    intent.breath = 1.2;
    if (phaseT > dur && c.n.fatigue < 0.25) _choose(c);
  }

  void _ask(double dt, BrainCtx c, {required bool food}) {
    final bowl = food ? c.w.food : c.w.water;
    if (bowl > 0.02) {
      _start(food ? Act.eat : Act.drink, c);
      return;
    }
    if (phase == 0) {
      if (_walkTo(c, tx, c.walk) || t > 20) {
        phase = 1;
        phaseT = 0;
      }
      return;
    }
    intent.posture = Posture.sit;
    intent.lookAtViewer = 1;
    intent.tailUp = c.isCat ? 0.5 : 0.2;
    nextMeow -= dt;
    if (nextMeow <= 0) {
      intent.mouth = 0.85;
      if (nextMeow < -0.6) {
        nextMeow = 3 + rng.nextDouble() * 3;
        petLog('meow for ${food ? 'food' : 'water'}');
      }
    }
    if (phaseT > 25) _choose(c);
  }

  void _dying(double dt, BrainCtx c) {
    if (phase == 0) {
      if (_walkTo(c, tx, c.walk * 0.35) || t > 40) {
        phase = 1;
        phaseT = 0;
      }
      return;
    }
    intent.posture = Posture.lie;
    intent.eyes = 0.35;
    intent.breath = 0.55;
    intent.tailUp = -1;
  }

  void _dead(BrainCtx c) {
    intent.posture = Posture.dead;
    intent.eyes = 0;
    intent.breath = 0;
    intent.tailUp = -1;
  }

  // ---------------- 統一後處理：年齡限制 ----------------
  void _post(BrainCtx c) {
    final life = c.life;
    intent.eyes = math.min(intent.eyes, life.eyesCanOpen);
    if (flinch > 0) {
      intent.earsBack = math.max(intent.earsBack, 0.8);
      intent.eyes = math.min(1, intent.eyes + 0.3);
    }
    if (c.n.fear > 0.3) intent.earsBack = math.max(intent.earsBack, c.n.fear);
    // 還不會走的新生兒：站姿 → 趴低爬行
    if (life.days < c.sp.walkDay * 0.85) {
      if (intent.posture == Posture.stand || intent.posture == Posture.dip || intent.posture == Posture.crouch) {
        intent.posture = Posture.loaf;
      }
      if (intent.posture == Posture.sit) intent.posture = Posture.lie;
    }
  }
}
