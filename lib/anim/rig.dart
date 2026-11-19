import 'dart:math' as math;

import '../sim/cat.dart';
import '../sim/motor.dart';
import '../sim/util.dart';
import 'spring.dart';

/// 2D 側面骨架。所有數值都經過彈簧或物理模擬，每一幀都由上一幀連續推算出來。
class _PostureTarget {
  const _PostureTarget(this.shoulder, this.hip, this.curl, this.frontTuck, this.hindTuck, this.reach, this.lie);
  final double shoulder, hip, curl, frontTuck, hindTuck, reach, lie;
}

const Map<Posture, _PostureTarget> _postures = {
  Posture.stand: _PostureTarget(1.0, 1.0, 0, 0, 0, 0, 0),
  Posture.sit: _PostureTarget(0.95, 0.28, 0.05, 0, 1, 0, 0),
  Posture.loaf: _PostureTarget(0.36, 0.36, 0.05, 1, 1, 0, 0),
  Posture.lie: _PostureTarget(0.24, 0.24, 0.12, 0.6, 0.6, 0.15, 1),
  Posture.curl: _PostureTarget(0.2, 0.2, 1.0, 1, 1, 0, 0.6),
  Posture.crouch: _PostureTarget(0.5, 0.62, 0, 0.35, 0.45, 0, 0),
  Posture.stretch: _PostureTarget(0.32, 1.0, -0.15, 0, 0, 1, 0),
  Posture.dip: _PostureTarget(0.78, 1.0, 0, 0, 0, 0, 0),
};

/// 身體在世界中的狀態（由懸浮視窗的物理決定，見 overlay/pet_body.dart）。
/// 骨架永遠在「身體座標」裡計算；被抱起、掉落時整隻貓再旋轉、平移到螢幕上。
class RigPose {
  const RigPose({this.angle = 0, this.legsFree = 0, this.tailFree = 0, this.struggle = 0});

  /// 身體相對世界的旋轉（逆時針、弧度）。用來算「重力在身體座標裡往哪個方向」。
  final double angle;

  /// 0 = 腳踩地；1 = 腳懸空，朝重力方向垂下
  final double legsFree;

  /// 0 = 一般尾巴；1 = 尾巴朝重力方向垂下
  final double tailFree;

  /// 0..1 掙扎：腳亂踢
  final double struggle;

  static const ground = RigPose();
}

class LegGeom {
  LegGeom(this.joint, this.knee, this.foot, {required this.front, required this.far});
  final V2 joint, knee, foot;
  final bool front, far;
}

/// 畫家需要的一幀幾何資料
class RigFrame {
  RigFrame({
    required this.facing,
    required this.hip,
    required this.shoulder,
    required this.spineCtrl,
    required this.torsoT,
    required this.chest,
    required this.neck,
    required this.head,
    required this.headR,
    required this.headTurn,
    required this.tilt,
    required this.eyeOpen,
    required this.pupil,
    required this.gaze,
    required this.mouth,
    required this.earsBack,
    required this.earScale,
    required this.earTwitch,
    required this.legs,
    required this.tail,
    required this.tailW0,
    required this.tailW1,
    required this.L,
  });
  final double facing;
  final V2 hip, shoulder, spineCtrl;
  final double torsoT, chest;
  final V2 neck, head;
  final double headR, headTurn, tilt, eyeOpen, pupil;
  final V2 gaze;
  final double mouth, earsBack, earScale, earTwitch;
  final List<LegGeom> legs;
  final List<V2> tail;
  final double tailW0, tailW1, L;

  /// 抱起的位置：胸口（前腳後方）
  V2 get holdPoint => shoulder + V2(-facing * L * 0.1, -torsoT * 0.05);

  /// 質心（約在背中間）
  V2 get com => V2.lerp(hip, shoulder, 0.55) + V2(0, torsoT * 0.1);
}

class _Foot {
  _Foot(this.x);
  double x;
  double y = 0;
  bool swinging = false;
  double sFrom = 0, sTo = 0, sT = 0, sDur = 0.25, lift = 0;
}

class PetRig {
  PetRig(double x) {
    for (var i = 0; i < 4; i++) {
      _feet.add(_Foot(x));
    }
    for (var i = 0; i < _tailN; i++) {
      _tail.add(V2(x - 10 - i * 2.0, 6));
      _tailPrev.add(V2(x - 10 - i * 2.0, 6));
    }
  }

  final math.Random _rng = math.Random(7);

  final Spring shoulderH = Spring(0.3), hipH = Spring(0.3), curl = Spring(0.5);
  final Spring frontTuck = Spring(1), hindTuck = Spring(1), reach = Spring(0), lie = Spring(0.5);
  final Spring facing = Spring(1);
  final Spring headDip = Spring(0), lookViewer = Spring(0), tilt = Spring(0);
  final Spring eyes = Spring(0), mouth = Spring(0), earsBack = Spring(0);
  final Spring tailUp = Spring(0), tailWag = Spring(0), tailLash = Spring(0), tailPuff = Spring(0);
  final Spring pawLift = Spring(0), knead = Spring(0), wiggle = Spring(0);
  final Spring pupil = Spring(0.5), gazeX = Spring(0), gazeY = Spring(0), bobS = Spring(0);
  final Spring legsFreeS = Spring(0), tailFreeS = Spring(0), struggleS = Spring(0);

  static const int _tailN = 8;
  final List<Spring> _kneeX = List.generate(4, (_) => Spring(0));
  final List<Spring> _kneeY = List.generate(4, (_) => Spring(0));
  bool _kneeInit = false;
  final List<V2?> _footPrev = List<V2?>.filled(4, null);
  final List<Spring> _hangX = List.generate(4, (_) => Spring(0));
  final List<Spring> _hangY = List.generate(4, (_) => Spring(0));
  bool _hangInit = false;

  /// 除錯：腳掌速度上限被觸發的次數與最大超出量（正常應該很少）
  int footClamps = 0;
  double footClampMax = 0;
  final List<_Foot> _feet = []; // 0 前近、1 前遠、2 後近、3 後遠
  final List<V2> _tail = [];
  final List<V2> _tailPrev = [];
  double time = 0;
  double _breath = 0;
  double _gait = 0;
  double _nextBlink = 2;
  double _blink = 0;
  double _nextTwitch = 3;
  double _twitch = 0;
  bool _tailInit = false;
  V2 _prevBase = V2.zero;

  RigFrame? last;

  /// 身體座標整體平移（落地時把身體座標對齊到螢幕位置用；畫面上不會有任何變化）
  void rebase(double dx) {
    if (dx == 0) return;
    final d = V2(dx, 0);
    for (final ft in _feet) {
      ft.x += dx;
      ft.sFrom += dx;
      ft.sTo += dx;
    }
    for (var i = 0; i < 4; i++) {
      final fp = _footPrev[i];
      if (fp != null) _footPrev[i] = fp + d;
      _kneeX[i].x += dx;
      _hangX[i].x += dx;
    }
    for (var i = 0; i < _tail.length; i++) {
      _tail[i] = _tail[i] + d;
      _tailPrev[i] = _tailPrev[i] + d;
    }
    _prevBase = _prevBase + d;
  }

  RigFrame update(double dt, MotorIntent it, double x, double vx, {double fear = 0, double brightness = 0.5, RigPose pose = RigPose.ground}) {
    dt = clampD(dt, 0, 0.05);
    time += dt;
    const g = 1.0;
    const L = CatBody.bodyLength;
    const legH = CatBody.legLength;
    final moving = vx.abs() > 1.5;
    legsFreeS.update(pose.legsFree, 0.08, dt);
    tailFreeS.update(pose.tailFree, 0.1, dt);
    struggleS.update(pose.struggle, 0.15, dt);
    // 重力方向（身體座標）：身體逆時針轉 angle，世界的「下」在身體座標是 (-sin, -cos)
    final gB = V2(-math.sin(pose.angle), -math.cos(pose.angle));

    // ---- 姿勢彈簧 ----
    final pt = _postures[it.posture]!;
    const ph = 0.22; // 坐下／起身約半秒
    shoulderH.update(pt.shoulder, ph, dt);
    hipH.update(pt.hip, ph * 1.15, dt);
    curl.update(pt.curl, 0.35, dt);
    frontTuck.update(pt.frontTuck, ph, dt);
    hindTuck.update(pt.hindTuck, ph, dt);
    reach.update(pt.reach, 0.3, dt);
    lie.update(pt.lie, 0.3, dt);
    final faceTarget = vx.abs() > 2 ? vx.sign : (it.faceDir ?? (facing.x >= 0 ? 1.0 : -1.0));
    facing.update(faceTarget, 0.12, dt);
    headDip.update(it.headDip, 0.15, dt);
    lookViewer.update(it.lookAtViewer, 0.2, dt);
    tilt.update(it.headTilt, 0.2, dt);
    eyes.update(it.eyes, 0.12, dt);
    mouth.update(it.mouth, 0.05, dt);
    earsBack.update(it.earsBack, 0.08, dt);
    tailUp.update(it.tailUp, 0.25, dt);
    tailWag.update(it.tailWag, 0.3, dt);
    tailLash.update(it.tailLash, 0.3, dt);
    tailPuff.update(it.tailPuff, 0.08, dt);
    pawLift.update(it.pawLift, 0.09, dt);
    knead.update(it.knead, 0.3, dt);
    wiggle.update(it.wiggle, 0.15, dt);
    // 瞳孔：暗處、害怕、玩耍時放大；亮處縮成細縫（貓）
    final play = it.wiggle > 0 || it.pawLift > 0.5 ? 0.3 : 0.0;
    pupil.update(clampD(0.18 + 0.6 * (1 - brightness) + 0.6 * fear + play, 0.15, 1), 0.4, dt);

    // ---- 眨眼、耳朵抽動、呼吸 ----
    _nextBlink -= dt;
    if (_nextBlink <= 0) {
      _blink = 0.18;
      _nextBlink = 2.5 + _rng.nextDouble() * 5;
    }
    _blink = math.max(0.0, _blink - dt);
    final blinkF = _blink > 0 ? 0.15 : 1.0;
    _nextTwitch -= dt;
    if (_nextTwitch <= 0) {
      _twitch = 0.25;
      _nextTwitch = 3 + _rng.nextDouble() * 6;
    }
    _twitch = math.max(0.0, _twitch - dt);
    final baseHz = it.eyes < 0.2 ? 0.33 : 0.42; // 每秒呼吸次數〔估〕
    _breath += dt * 2 * math.pi * baseHz * it.breath;
    final chest = 1 + 0.035 * math.sin(_breath) * math.min(1, it.breath);

    // ---- 身體 ----
    final f = facing.x;
    final c = curl.x;
    _gait += dt * vx.abs() / math.max(1, L * 0.35) * math.pi;
    bobS.update(moving ? 1 : 0, 0.15, dt);
    final bob = math.sin(_gait * 2).abs() * legH * 0.05 * bobS.x;
    final wig = math.sin(time * 18) * L * 0.025 * wiggle.x;
    final T = L * 0.25 * (1 + 0.25 * (1 - g));
    final hip = V2(x - f * L * 0.42 * (1 - 0.45 * c) + wig, legH * hipH.x + T * 0.3 + bob);
    final shoulder = V2(x + f * L * 0.38 * (1 - 0.45 * c) + f * L * 0.12 * reach.x, legH * shoulderH.x + T * 0.3 + bob);
    final mid = V2.lerp(hip, shoulder, 0.5);
    final spineCtrl = V2(mid.x, mid.y + T * 0.15 + c * L * 0.22 - reach.x * T * 0.2);

    // ---- 頭 ----
    const headR = L * 0.19;
    final neck = shoulder + V2(f * L * 0.06, T * 0.5);
    var head = neck + V2(f * L * 0.14, L * 0.15 * (0.6 + 0.4 * shoulderH.x));
    final dipHead = V2(shoulder.x + f * L * 0.26, headR * 0.95);
    head = V2.lerp(head, dipHead, headDip.x * (1 - c));
    final curlHead = V2(hip.x + f * L * 0.18, headR * 0.95);
    head = V2.lerp(head, curlHead, c * 0.85);
    final lieHead = V2(shoulder.x + f * L * 0.22, headR * 1.05);
    head = V2.lerp(head, lieHead, lie.x * (1 - c) * 0.6);
    final turn = clampD(math.max(lookViewer.x, 1 - f.abs()), 0, 1);

    // 視線
    var gz = const V2(0, 0);
    if (it.gazeX != null && lookViewer.x < 0.8) {
      gz = V2(it.gazeX! - head.x, it.gazeY - head.y).normalized();
    }
    gazeX.update(gz.x, 0.1, dt);
    gazeY.update(gz.y, 0.1, dt);

    // ---- 腳 ----
    final legs = <LegGeom>[];
    final frontJ = shoulder + V2(0, -T * 0.25);
    final hindJ = hip + V2(0, -T * 0.2);
    final stride = moving ? clampD(vx.abs() * 0.16, 1.5, 7) * math.max(0.5, g) : 1.2 * g + 0.4;
    var swinging = _feet.where((ft) => ft.swinging).length;
    for (var i = 0; i < 4; i++) {
      final front = i < 2;
      final far = i.isOdd;
      final j = (front ? frontJ : hindJ) + V2(far ? -f * L * 0.05 : 0, 0);
      final tuck = front ? frontTuck.x : hindTuck.x;
      var homeX = j.x + f * (front ? 0.02 : -0.02) * L + vx * 0.08;
      homeX += f * L * 0.32 * (front ? reach.x : 0);
      homeX += lie.x * f * L * (front ? 0.36 : -0.3);
      homeX = lerpD(homeX, j.x + f * L * (front ? 0.05 : -0.06), tuck * (1 - lie.x));
      final ft = _feet[i];
      if (ft.swinging) {
        ft.sT += dt;
        final u = clampD(ft.sT / ft.sDur, 0, 1);
        ft.x = lerpD(ft.sFrom, ft.sTo, smooth01(u));
        ft.y = math.sin(math.pi * u) * ft.lift;
        if (u >= 1) {
          ft.swinging = false;
          ft.y = 0;
          swinging--;
        }
      } else {
        final partner = _feet[i ^ 1];
        if ((ft.x - homeX).abs() > stride && !partner.swinging && swinging < 2) {
          ft.swinging = true;
          swinging++;
          ft.sFrom = ft.x;
          ft.sTo = homeX + (moving ? vx * 0.08 : 0);
          ft.sT = 0;
          final baseDur = moving ? clampD(0.3 - vx.abs() * 0.0025, 0.12, 0.3) : 0.2;
          // 跨得越遠就用越久，腳掌速度有上限（擺動期約為身體速度的 2 倍，不會瞬移）
          ft.sDur = math.max(baseDur, (ft.sTo - ft.sFrom).abs() / 75);
          ft.lift = legH * (moving ? 0.28 : 0.12) * (1 - 0.7 * tuck);
        } else if (!moving && (ft.x - homeX).abs() < stride) {
          ft.x = lerpD(ft.x, homeX, 1 - math.exp(-dt * 3)); // 靜止時腳慢慢放好
        }
      }
      var fx = ft.x, fy = ft.y;
      if (front) {
        final k = knead.x * (math.sin(time * 4 + (far ? math.pi : 0))).clamp(0.0, 1.0);
        fy += k * legH * 0.12;
        if (!far && pawLift.x > 0.01) {
          final toFace = clampD(hindTuck.x * (1 - frontTuck.x), 0, 1);
          final batPos = V2(j.x + f * L * 0.22, legH * 0.75);
          final facePos = head + V2(f * headR * 0.3, -headR * 0.7);
          final target = V2.lerp(batPos, facePos, toFace);
          fx = lerpD(fx, target.x, pawLift.x);
          fy = lerpD(fy, target.y, pawLift.x);
        }
      }
      var foot = V2(fx, math.max(0.0, fy));
      // 懸空：腳朝重力方向垂下（有彈簧延遲），掙扎時亂踢
      final reachLen = legH * 1.12 * (front ? 0.84 : 0.92);
      final perpG = V2(-gB.y, gB.x);
      final paddle = math.sin(time * 9 + i * 1.7) * legH * 0.3 * struggleS.x;
      final hangT = j + gB * reachLen + perpG * paddle;
      if (!_hangInit) {
        _hangX[i].x = hangT.x;
        _hangY[i].x = hangT.y;
      }
      _hangX[i].update(hangT.x, 0.05, dt);
      _hangY[i].update(hangT.y, 0.05, dt);
      final lf = legsFreeS.x;
      if (lf > 1e-4) foot = V2.lerp(foot, V2(_hangX[i].x, _hangY[i].x), clampD(lf, 0, 1));
      // 最後保險：腳掌每幀最多比身體多移動 2.2 單位，保證畫面不會跳
      final fp = _footPrev[i];
      if (fp != null) {
        final delta = foot - fp;
        final maxStep = 2.2 + vx.abs() * dt;
        final dl = delta.length;
        if (dl > maxStep) {
          footClamps++;
          footClampMax = math.max(footClampMax, dl - maxStep);
          foot = fp + delta * (maxStep / dl);
        }
      }
      _footPrev[i] = foot;
      final rawKnee = _knee(j, foot, legH, kneeForward: !front, f: f);
      if (!_kneeInit) {
        _kneeX[i].x = rawKnee.x;
        _kneeY[i].x = rawKnee.y;
      }
      // 膝蓋再過一層很短的彈簧：彎曲方向改變時用 0.1 秒左右轉過去，不會一幀翻面
      _kneeX[i].update(rawKnee.x, 0.035, dt);
      _kneeY[i].update(rawKnee.y, 0.035, dt);
      legs.add(LegGeom(j, V2(_kneeX[i].x, _kneeY[i].x), foot, front: front, far: far));
    }

    _kneeInit = true;
    _hangInit = true;

    // ---- 尾巴（鏈條物理） ----
    const tailLen = L * 0.95;
    final seg = tailLen / _tailN;
    final base = hip + V2(-f * L * 0.08, T * 0.35);
    final up = tailUp.x;
    var ang = lerpD(-0.35, up >= 0 ? 1.35 : -1.2, up.abs()); // 0 = 水平往後
    final tf = clampD(tailFreeS.x, 0, 1);
    if (tf > 1e-4 && f.abs() > 0.05) {
      final hangAng = math.atan2(gB.y, -f * gB.x); // 讓尾巴方向 (-f·cos a, sin a) = 重力方向
      ang += wrapAngle(hangAng - ang) * tf;
    }
    final targets = <V2>[];
    var p = base;
    for (var i = 0; i < _tailN; i++) {
      final k = (i + 1) / _tailN;
      final upCurve = lerpD(0.12, -0.18 * up, smooth01((up - 0.1) / 0.4)); // 尾巴越翹，尾端越往前勾（連續）
      final curve = (upCurve * (1 - c) + c * -0.38) * (1 - tf);
      ang += curve;
      final wag = math.sin(time * 16 - i * 0.5) * 0.5 * tailWag.x * k;
      final lash = math.sin(time * 3.5 - i * 0.35) * 0.55 * tailLash.x * k;
      final a = ang + wag + lash;
      p = p + V2(-f * math.cos(a), math.sin(a)) * seg;
      targets.add(p);
    }
    if (!_tailInit) {
      for (var i = 0; i < _tailN; i++) {
        _tail[i] = targets[i];
        _tailPrev[i] = targets[i];
      }
      _tailInit = true;
    }
    final stiff = 1 - math.exp(-dt * 18);
    final maxStep = 1.4 + base.dist(_prevBase); // 每幀最多比尾巴根部多移動 1.4 單位
    _prevBase = base;
    var prev = base;
    for (var i = 0; i < _tailN; i++) {
      final cur = _tail[i];
      var vel = (cur - _tailPrev[i]) * 0.65;
      final vl = vel.length;
      if (vl > 1.2) vel = vel * (1.2 / vl); // 尾巴甩動速度上限
      var nxt = cur + vel + (targets[i] - cur) * stiff;
      final disp = nxt - cur;
      final dl = disp.length;
      if (dl > maxStep) nxt = cur + disp * (maxStep / dl);
      final d = nxt - prev;
      final l = d.length;
      if (l > 1e-6) nxt = prev + d * (seg / l);
      _tailPrev[i] = cur;
      _tail[i] = nxt;
      prev = nxt;
    }

    final fr = RigFrame(
      facing: f,
      hip: hip,
      shoulder: shoulder,
      spineCtrl: spineCtrl,
      torsoT: T,
      chest: chest,
      neck: neck,
      head: head,
      headR: headR,
      headTurn: turn,
      tilt: tilt.x * 0.35,
      eyeOpen: clampD(eyes.x, 0, 1) * blinkF,
      pupil: clampD(pupil.x, 0.12, 1),
      gaze: V2(gazeX.x, gazeY.x),
      mouth: clampD(mouth.x, 0, 1),
      earsBack: clampD(earsBack.x, 0, 1),
      earScale: 1,
      earTwitch: _twitch > 0 ? math.sin(_twitch * 60) * 0.15 : 0,
      legs: legs,
      tail: List<V2>.unmodifiable([base, ..._tail]),
      tailW0: T * 0.2 * (1 + 1.4 * tailPuff.x),
      tailW1: T * 0.09 * (1 + 1.4 * tailPuff.x),
      L: L,
    );
    last = fr;
    return fr;
  }

  /// 兩段式 IK：前腳肘往後彎，後腳膝蓋往前彎
  static V2 _knee(V2 j, V2 foot, double legH, {required bool kneeForward, required double f}) {
    final l1 = legH * 0.56, l2 = legH * 0.56;
    final dv = foot - j;
    final rawD = dv.length;
    final d = clampD(rawD, (l1 - l2).abs() + 1e-3, l1 + l2 - 1e-3);
    final a = (l1 * l1 - l2 * l2 + d * d) / (2 * d);
    final h = math.sqrt(math.max(0.0, l1 * l1 - a * a));
    // 腳收得離關節很近時，腿的「方向」幾乎沒有定義，一點點移動就會讓膝蓋亂轉；
    // 這時把參考方向平滑地拉向正下方。
    const down = V2(0, -1);
    final raw = rawD > 1e-6 ? dv * (1 / rawD) : down;
    final blend = V2.lerp(down, raw, smooth01(rawD / (0.35 * legH)));
    final dir = blend.length < 1e-3 ? down : blend.normalized();
    final p = j + dir * a;
    final perp = V2(-dir.y, dir.x);
    // 膝蓋往哪邊彎用「連續權重」，不用 if 翻面：轉身經過正面、或腳伸成水平時，膝蓋才不會瞬間跳到另一邊
    final want = kneeForward ? f : -f;
    final side = clampD(perp.x * want * 2.5, -1, 1);
    return p + perp * (h * side);
  }
}
