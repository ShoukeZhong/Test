import 'util.dart';

/// 房間裡的東西。x 是世界座標（畫面寬 = 100），地板 y = 0。
enum WasteKind { urine, feces }

class Waste {
  Waste(this.kind, this.x);
  final WasteKind kind;
  final double x;
  Map<String, dynamic> toJson() => {'k': kind.index, 'x': x};
  factory Waste.fromJson(Map<String, dynamic> m) =>
      Waste(WasteKind.values[(m['k'] as num).toInt()], (m['x'] as num).toDouble());
}

class Ball {
  double x = 92, y = 0, vx = 0, vy = 0;
  bool held = false;
  static const double r = 2.2;

  void update(double dt) {
    if (held) return;
    vy -= 220 * dt;
    x += vx * dt;
    y += vy * dt;
    if (y <= 0) {
      y = 0;
      if (vy.abs() > 25) {
        vy = -vy * 0.45;
      } else {
        vy = 0;
      }
      vx *= 0.985;
      if (vx.abs() < 0.5) vx = 0;
    }
    if (x < World.minX) {
      x = World.minX;
      vx = vx.abs() * 0.5;
    }
    if (x > World.maxX) {
      x = World.maxX;
      vx = -vx.abs() * 0.5;
    }
  }

  bool get moving => !held && (vx.abs() > 3 || y > 0.5);
}

class World {
  static const double minX = 6;
  static const double maxX = 94;
  static const double toiletX = 12; // 貓砂盆／尿布墊中心
  static const double toiletHalfW = 8;
  static const double bedX = 30;
  static const double nestX = 55;
  static const double waterX = 70;
  static const double foodX = 84;
  static const int toiletRefuseCount = 5; // 太髒就不用

  double food = 0.6; // 碗：0..1（1 = 滿碗，約一天份）
  double water = 0.8;
  final List<Waste> toilet = [];
  final List<Waste> floor = [];
  final Ball ball = Ball();

  int get mess => floor.length;

  void update(double dt) => ball.update(dt);

  Map<String, dynamic> toJson() => {
        'food': food,
        'water': water,
        'toilet': toilet.map((w) => w.toJson()).toList(),
        'floor': floor.map((w) => w.toJson()).toList(),
      };

  void loadJson(Map<String, dynamic> m) {
    food = (m['food'] as num).toDouble();
    water = (m['water'] as num).toDouble();
    toilet
      ..clear()
      ..addAll((m['toilet'] as List).map((e) => Waste.fromJson(Map<String, dynamic>.from(e as Map))));
    floor
      ..clear()
      ..addAll((m['floor'] as List).map((e) => Waste.fromJson(Map<String, dynamic>.from(e as Map))));
  }

  /// 撥動清理：移除最靠近 x 的排泄物（範圍內）。回傳是否有清到。
  bool scoopNear(double x, {bool inToilet = false, double range = 6}) {
    final list = inToilet ? toilet : floor;
    if (list.isEmpty) return false;
    list.sort((a, b) => (a.x - x).abs().compareTo((b.x - x).abs()));
    if ((list.first.x - x).abs() > range) return false;
    list.removeAt(0);
    return true;
  }

  void pourFood(double amount) => food = clampD(food + amount, 0, 1);
  void pourWater(double amount) => water = clampD(water + amount, 0, 1);
}
