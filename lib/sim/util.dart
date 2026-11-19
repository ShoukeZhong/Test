import 'dart:math' as math;

double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);
double lerpD(double a, double b, double t) => a + (b - a) * t;
double smooth01(double t) {
  final x = clampD(t, 0, 1);
  return x * x * (3 - 2 * x);
}

/// 二維向量（世界座標：x 向右，y 向上，地板 y = 0）。
class V2 {
  const V2(this.x, this.y);
  final double x;
  final double y;
  static const zero = V2(0, 0);
  V2 operator +(V2 o) => V2(x + o.x, y + o.y);
  V2 operator -(V2 o) => V2(x - o.x, y - o.y);
  V2 operator *(double k) => V2(x * k, y * k);
  double get length => math.sqrt(x * x + y * y);
  double dist(V2 o) => (this - o).length;
  V2 normalized() {
    final l = length;
    return l < 1e-9 ? const V2(0, 0) : V2(x / l, y / l);
  }

  static V2 lerp(V2 a, V2 b, double t) => V2(lerpD(a.x, b.x, t), lerpD(a.y, b.y, t));

  /// 逆時針旋轉（y 向上）
  V2 rotate(double a) {
    final c = math.cos(a), s = math.sin(a);
    return V2(x * c - y * s, x * s + y * c);
  }

  /// 二維外積（純量）
  double cross(V2 o) => x * o.y - y * o.x;
  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

const double kMinute = 60;
const double kHour = 3600;

/// 角度差，結果在 (-π, π]
double wrapAngle(double a) {
  var x = a % (2 * math.pi);
  if (x > math.pi) x -= 2 * math.pi;
  if (x <= -math.pi) x += 2 * math.pi;
  return x;
}

/// release 版也會出現在 logcat，CI 用來檢查行為
void petLog(String msg) {
  // ignore: avoid_print
  print('[pet] $msg');
}
