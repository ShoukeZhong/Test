import 'dart:math' as math;

/// 臨界阻尼彈簧（Daniel Holden, "Spring-It-On"）。
/// 目標可以突然改變，但位置與速度永遠連續——這是「動作不跳格」的基礎。
class Spring {
  Spring(this.x);

  double x;
  double v = 0;

  void update(double target, double halflife, double dt) {
    final y = 2 * math.ln2 / math.max(halflife, 1e-4);
    final j0 = x - target;
    final j1 = v + j0 * y;
    final e = math.exp(-y * dt);
    x = e * (j0 + j1 * dt) + target;
    v = e * (v - j1 * y * dt);
  }
}
