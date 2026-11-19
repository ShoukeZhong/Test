import 'dart:math' as math;

import 'util.dart';
import 'world.dart';

/// 姿勢只是「目標」，骨架用彈簧慢慢過去，所以切換時畫面不會跳。
enum Posture { stand, sit, loaf, lie, curl, crouch, squat, stretch, dip, dead }

/// 行為層每一幀輸出的「運動意圖」——連續數值，不是動作片段。
class MotorIntent {
  double? targetX;
  double speed = 18;
  Posture posture = Posture.stand;
  double? faceDir;
  double lookAtViewer = 0;
  double? gazeX;
  double gazeY = 4;
  double headDip = 0;
  double lap = 0;
  double chew = 0;
  double tailUp = 0;
  double tailWag = 0;
  double tailLash = 0;
  double tailPuff = 0;
  double earsBack = 0;
  double eyes = 1;
  double mouth = 0;
  double pawLift = 0;
  double knead = 0;
  double dig = 0;
  double breath = 1;
  double wiggle = 0;
  double headTilt = 0;
  bool purr = false;

  void reset() {
    targetX = null;
    speed = 18;
    posture = Posture.stand;
    faceDir = null;
    lookAtViewer = 0;
    gazeX = null;
    gazeY = 4;
    headDip = 0;
    lap = 0;
    chew = 0;
    tailUp = 0;
    tailWag = 0;
    tailLash = 0;
    tailPuff = 0;
    earsBack = 0;
    eyes = 1;
    mouth = 0;
    pawLift = 0;
    knead = 0;
    dig = 0;
    breath = 1;
    wiggle = 0;
    headTilt = 0;
    purr = false;
  }
}

/// 位置與速度：有加速度上限，所以起步、停下、轉身都是連續的。
class Locomotion {
  double x = World.nestX;
  double vx = 0;
  double facing = 1; // 目標朝向 ±1（骨架會平滑轉身）
  bool clampToRoom = true;

  bool arrived(double tx, {double tol = 1.2}) => (x - tx).abs() < tol && vx.abs() < 3;

  void update(double dt, MotorIntent it, {required double mobility}) {
    var desired = 0.0;
    final tx = it.targetX;
    if (tx != null) {
      final dx = tx - x;
      if (dx.abs() > 0.4) {
        const decel = 90.0;
        final brake = math.sqrt(2 * decel * dx.abs());
        desired = dx.sign * math.min(it.speed * mobility, brake);
        facing = dx.sign;
      }
    }
    if (desired == 0 && it.faceDir != null) facing = it.faceDir!.sign == 0 ? facing : it.faceDir!.sign;
    // 轉身時先慢下來
    if (vx != 0 && desired != 0 && vx.sign != desired.sign) desired *= 0.2;
    final accel = 70 * math.max(0.4, mobility);
    final braking = desired.abs() < vx.abs() || (desired != 0 && vx != 0 && desired.sign != vx.sign);
    final maxDv = (braking ? accel * 1.6 : accel) * dt;
    vx += clampD(desired - vx, -maxDv, maxDv);
    x += vx * dt;
    if (clampToRoom) {
      if ((x <= World.minX && vx < 0) || (x >= World.maxX && vx > 0)) vx = 0;
      x = clampD(x, World.minX, World.maxX);
    }
  }
}
