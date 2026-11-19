import 'dart:math' as math;

import '../anim/rig.dart';
import '../anim/spring.dart';
import '../sim/cat.dart';
import '../sim/util.dart';

enum CarryMode { ground, held, air }

/// 身體座標 → 世界座標（世界：螢幕上的單位，x 向右、y 向上、地板 y = 0）。
/// 把身體上的 [pivotB] 放到世界的 [pivotW]，再繞它逆時針轉 [angle]。
class Placement {
  const Placement(this.pivotB, this.pivotW, this.angle);
  final V2 pivotB, pivotW;
  final double angle;

  V2 map(V2 b) => pivotW + (b - pivotB).rotate(angle);
  V2 unmap(V2 w) => pivotB + (w - pivotW).rotate(-angle);
}

/// 被抱起、晃動、放手、掉落、落地的物理。純 Dart，方便單元測試。
///
/// - 抱著：物理擺（pivot 在胸口、跟著手指），手指加速度會讓身體晃（等效重力 g − a）。
/// - 放手：拋體運動 + 翻正反射（臨界阻尼彈簧把身體轉回腳朝下）。
/// - 落地：找身體最低點碰到地板的那一刻，切回地面模式；剩下的傾斜和高度用彈簧收掉，畫面不跳。
class PetBody {
  CarryMode mode = CarryMode.ground;
  Placement placement = const Placement(V2.zero, V2.zero, 0);

  double angle = 0;
  double omega = 0;

  /// 抱著：胸口在世界的位置；空中：質心在世界的位置
  V2 pos = V2.zero;
  V2 vel = V2.zero;
  V2 _finger = V2.zero;
  V2 _grabOffset = V2.zero;
  V2? _prevPivot;
  V2 _pivotVel = V2.zero;
  V2 _pivotAcc = V2.zero;
  bool _justReleased = false;
  double heldT = 0;
  double airT = 0;
  double sinceLand = 99;

  final Spring _resY = Spring(0);
  final Spring _resA = Spring(0);

  // ---- 每幀輸出（呼叫端要處理）----
  /// 落地那一幀的撞擊速度；其他幀 -1
  double landImpact = -1;

  /// 落地那一幀：身體座標要平移多少（呼叫端：loco.x += dx、rig.rebase(dx)）
  double rebaseDx = 0;

  /// 落地時的水平速度（交給 Locomotion 延續）
  double landVx = 0;

  /// 最高能被拋到哪（世界單位）
  double maxSpeed = 700;

  bool get carried => mode != CarryMode.ground;

  /// 落地後傾斜、高度都收乾淨了（可以把視窗縮回小的）
  bool get settled => mode == CarryMode.ground && _resY.x.abs() < 0.05 && _resA.x.abs() < 0.01 && sinceLand > 0.4;

  RigPose pose({double struggle = 0}) => switch (mode) {
        CarryMode.ground => RigPose(angle: _resA.x),
        CarryMode.held => RigPose(angle: angle, legsFree: 1, tailFree: 1, struggle: struggle),
        CarryMode.air => RigPose(angle: angle, legsFree: 1, tailFree: 0.25),
      };

  /// 長按：從胸口抱起來
  void grab(V2 finger, RigFrame f) {
    if (mode == CarryMode.held) return;
    final hold = placement.map(f.holdPoint);
    final wasAir = mode == CarryMode.air; // 半空中接住：保留角度和轉速
    if (!wasAir) {
      angle = placement.angle;
      omega = 0;
    }
    mode = CarryMode.held;
    _finger = finger;
    _grabOffset = hold - finger;
    pos = hold;
    _prevPivot = null;
    _pivotVel = wasAir ? vel : V2.zero;
    _pivotAcc = V2.zero;
    heldT = 0;
    petLog('grab at ${finger.x.toStringAsFixed(1)},${finger.y.toStringAsFixed(1)}');
  }

  void moveFinger(V2 finger) => _finger = finger;

  void release() {
    if (mode != CarryMode.held) return;
    mode = CarryMode.air;
    airT = 0;
    _justReleased = true;
  }

  /// 每幀：[f] 是這一幀的骨架（身體座標）。回傳把它放到世界的方式。
  Placement update(double dt, RigFrame f, {double struggle = 0, required double minX, required double maxX, required double topY}) {
    landImpact = -1;
    rebaseDx = 0;
    dt = clampD(dt, 0, 0.05);
    switch (mode) {
      case CarryMode.ground:
        sinceLand += dt;
        _resY.update(0, 0.06, dt);
        _resA.update(0, 0.07, dt);
        final pb = V2(f.com.x, 0);
        placement = Placement(pb, V2(pb.x, _resY.x), _resA.x);
      case CarryMode.held:
        _held(dt, f, struggle);
      case CarryMode.air:
        _air(dt, f, minX, maxX, topY);
    }
    return placement;
  }

  void _held(double dt, RigFrame f, double struggle) {
    heldT += dt;
    _grabOffset = _grabOffset * math.exp(-dt / 0.12); // 約 0.3 秒把胸口移到手指下
    var pivot = _finger + _grabOffset;
    // 手指太低時把貓往上提，不讓身體穿過地板
    final lowRel = lowestY(f, Placement(f.holdPoint, V2.zero, angle));
    pivot = V2(pivot.x, math.max(pivot.y, -lowRel + 0.5));
    if (_prevPivot != null && dt > 0) {
      final v = (pivot - _prevPivot!) * (1 / dt);
      var a = (v - _pivotVel) * (1 / dt);
      final al = a.length;
      if (al > 4000) a = a * (4000 / al);
      _pivotVel = V2.lerp(_pivotVel, v, 0.5);
      _pivotAcc = V2.lerp(_pivotAcc, a, 0.4);
    }
    _prevPivot = pivot;
    pos = pivot;

    // 物理擺：α = (r × g_eff) / (|r|² + k²) − 阻尼 + 掙扎
    final rB = f.com - f.holdPoint;
    final k2 = math.pow(f.L * 0.3, 2).toDouble(); // 迴轉半徑約 0.3 體長〔估〕
    const n = 4;
    final h = dt / n;
    for (var i = 0; i < n; i++) {
      final r = rB.rotate(angle);
      final gEff = V2(-_pivotAcc.x, -CatBody.gravity - _pivotAcc.y);
      final rl2 = r.x * r.x + r.y * r.y;
      final w0 = math.sqrt(CatBody.gravity * math.sqrt(rl2) / (rl2 + k2));
      var alpha = r.cross(gEff) / (rl2 + k2);
      alpha -= 2 * 0.25 * w0 * omega; // 阻尼比 0.25〔估〕
      alpha += struggle * w0 * w0 * 0.35 * (math.sin(heldT * 7.3) + 0.6 * math.sin(heldT * 12.1 + 1));
      omega = clampD(omega + alpha * h, -15, 15);
      angle += omega * h;
    }
    placement = Placement(f.holdPoint, pos, angle);
  }

  void _air(double dt, RigFrame f, double minX, double maxX, double topY) {
    if (_justReleased) {
      // 支點從胸口換到質心：同一個 placement，畫面不跳
      final rW = (f.com - f.holdPoint).rotate(angle);
      pos = pos + rW;
      vel = _pivotVel + V2(-omega * rW.y, omega * rW.x);
      final vl = vel.length;
      if (vl > maxSpeed) vel = vel * (maxSpeed / vl);
      _justReleased = false;
      petLog('release v=${vel.x.toStringAsFixed(0)},${vel.y.toStringAsFixed(0)} angle=${angle.toStringAsFixed(2)}');
    }
    airT += dt;
    const n = 4;
    final h = dt / n;
    for (var i = 0; i < n; i++) {
      vel = vel + const V2(0, -CatBody.gravity) * h;
      pos = pos + vel * h;
      // 翻正反射：放手後約 0.05 秒開始，把身體轉回腳朝下（臨界阻尼）〔估；機制見 Kane & Scher 1969〕
      if (airT > 0.05) {
        final target = angle - wrapAngle(angle);
        final s = Spring(angle)..v = omega;
        s.update(target, 0.1, h);
        angle = s.x;
        omega = s.v;
      }
      // 螢幕邊緣：往外飛就反彈（只改速度、不改位置，畫面不跳）
      if ((pos.x < minX && vel.x < 0) || (pos.x > maxX && vel.x > 0)) vel = V2(-vel.x * 0.4, vel.y);
      if (pos.y > topY && vel.y > 0) vel = V2(vel.x, -vel.y * 0.3);
      placement = Placement(f.com, pos, angle);
      final low = lowestY(f, placement);
      if (low <= 0 && vel.y <= 0) {
        _land(f, low);
        return;
      }
    }
    placement = Placement(f.com, pos, angle);
  }

  void _land(RigFrame f, double low) {
    pos = V2(pos.x, pos.y - low); // 最低點剛好碰地
    placement = Placement(f.com, pos, angle);
    landImpact = math.max(0.0, -vel.y);
    landVx = vel.x;
    final floorB = V2(f.com.x, 0);
    final w = placement.map(floorB);
    rebaseDx = w.x - floorB.x;
    _resY
      ..x = w.y
      ..v = 0;
    _resA
      ..x = wrapAngle(angle)
      ..v = 0;
    mode = CarryMode.ground;
    angle = 0;
    omega = 0;
    sinceLand = 0;
    petLog('landed impact=${landImpact.toStringAsFixed(0)} tilt=${_resA.x.toStringAsFixed(2)}');
  }

  /// 身體最低點在世界的高度（腳、膝蓋、軀幹下緣、頭下緣；不含尾巴）
  static double lowestY(RigFrame f, Placement p) {
    var low = double.infinity;
    void t(V2 b) {
      final y = p.map(b).y;
      if (y < low) low = y;
    }

    for (final l in f.legs) {
      t(l.foot);
      t(l.knee);
    }
    final n = V2(0, f.torsoT * 0.55);
    t(f.hip - n);
    t(f.hip + n);
    t(f.shoulder - n);
    t(f.shoulder + n);
    t(f.head - V2(0, f.headR));
    t(f.head + V2(0, f.headR));
    return low;
  }
}
