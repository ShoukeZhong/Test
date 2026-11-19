import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../anim/pet_painter.dart';
import '../anim/rig.dart';
import '../sim/species.dart';
import '../sim/util.dart';
import '../sim/world.dart';

class Particle {
  Particle(this.pos, this.vel, this.color, this.life, this.r);
  Offset pos;
  Offset vel;
  final Color color;
  double life;
  final double r;
}

/// 畫面上需要的一切（由 PetWorldPage 每幀更新）
class SceneModel {
  SceneModel(this.species, this.coat, this.motherCoat);
  final Species species;
  final Coat coat;
  final Coat motherCoat;
  World? world;
  RigFrame? pet;
  RigFrame? mother;
  bool motherVisible = false;
  bool motherCares = false;
  double ageDays = 0;
  bool dead = false;
  double deadFade = 0;
  double hour = 12;
  Offset bagPos = Offset.zero;
  Offset jugPos = Offset.zero;
  double bagTilt = 0;
  double jugTilt = 0;
  final List<Particle> particles = [];
  Offset? finger;
  double viewLeft = 0;
  double viewWidth = 100;
  WorldView view(Size size) => WorldView(size, left: viewLeft, width: viewWidth);
}

class ScenePainter extends CustomPainter {
  ScenePainter(this.m, Listenable repaint) : super(repaint: repaint);
  final SceneModel m;

  static Rect bagRect(Size size) => Rect.fromCenter(center: Offset(size.width * 0.80, size.height * 0.20), width: size.width * 0.13, height: size.width * 0.17);
  static Rect jugRect(Size size) => Rect.fromCenter(center: Offset(size.width * 0.93, size.height * 0.20), width: size.width * 0.09, height: size.width * 0.15);

  @override
  void paint(Canvas c, Size size) {
    final v = m.view(size);
    final w = m.world;
    final day = _daylight(m.hour);

    // 牆與地板
    final wall = Color.lerp(const Color(0xFF242A3A), const Color(0xFFE8E2D6), day)!;
    final floor = Color.lerp(const Color(0xFF3A2F27), const Color(0xFFC9A57F), day)!;
    c.drawRect(Rect.fromLTWH(0, 0, size.width, v.floorY), Paint()..color = wall);
    c.drawRect(Rect.fromLTWH(0, v.floorY, size.width, size.height - v.floorY), Paint()..color = floor);
    c.drawRect(Rect.fromLTWH(0, v.floorY - 6, size.width, 6), Paint()..color = Color.lerp(wall, Colors.black, 0.18)!);
    _window(c, size, day);
    _shelf(c, size, day);

    if (w != null) {
      _bed(c, v, day);
      if (m.motherVisible || m.ageDays < 60) _nest(c, v, m.ageDays);
      _toiletBack(c, v, w);
      _bowl(c, v, World.waterX, w.water, const Color(0xFF7FB7E6), water: true);
      _bowl(c, v, World.foodX, w.food, const Color(0xFF9B5E2E), water: false);
      for (final waste in w.floor) {
        _waste(c, v, waste, onFloor: true);
      }
    }

    if (m.mother != null && m.motherVisible) {
      PetPainterKit.paint(c, v, m.mother!, m.motherCoat, ageDays: 1500);
    }
    if (m.pet != null) {
      PetPainterKit.paint(c, v, m.pet!, m.coat, dim: m.deadFade * 0.35, ageDays: m.ageDays);
    }
    if (w != null) {
      _toiletFront(c, v, w);
      _ball(c, v, w.ball);
    }

    // 粒子（飼料、水）
    for (final p in m.particles) {
      c.drawCircle(p.pos, p.r, Paint()..color = p.color);
    }
    // 拿在手上的飼料袋、水壺
    _bag(c, size);
    _jug(c, size);

    // 夜晚
    if (day < 0.95) {
      c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0A1030).withValues(alpha: (1 - day) * 0.28));
    }
    if (m.deadFade > 0) {
      c.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: 0.35 * m.deadFade));
    }
  }

  double _daylight(double hour) {
    // 6 點到 18 點亮；清晨與黃昏漸變
    final h = hour % 24;
    if (h >= 7 && h <= 17) return 1;
    if (h > 17 && h < 19.5) return 1 - (h - 17) / 2.5 * 0.8;
    if (h > 4.5 && h < 7) return 0.2 + (h - 4.5) / 2.5 * 0.8;
    return 0.2;
  }

  void _window(Canvas c, Size size, double day) {
    final r = Rect.fromLTWH(size.width * 0.08, size.height * 0.1, size.width * 0.3, size.height * 0.22);
    final sky = Color.lerp(const Color(0xFF0E1530), const Color(0xFFAED6F1), day)!;
    c.drawRRect(RRect.fromRectAndRadius(r.inflate(6), const Radius.circular(4)), Paint()..color = const Color(0xFFF7F3EA).withValues(alpha: 0.9));
    c.drawRect(r, Paint()..color = sky);
    if (day < 0.5) {
      c.drawCircle(r.topRight + Offset(-r.width * 0.25, r.height * 0.3), r.width * 0.07, Paint()..color = const Color(0xFFF4F1DE));
    } else {
      c.drawCircle(r.topLeft + Offset(r.width * 0.25, r.height * 0.35), r.width * 0.08, Paint()..color = const Color(0xFFFFF3B0).withValues(alpha: day));
    }
    final frame = Paint()
      ..color = const Color(0xFFF7F3EA)
      ..strokeWidth = 5;
    c.drawLine(r.topCenter, r.bottomCenter, frame);
    c.drawLine(r.centerLeft, r.centerRight, frame);
  }

  void _shelf(Canvas c, Size size, double day) {
    final y = size.height * 0.28;
    c.drawRect(Rect.fromLTWH(size.width * 0.70, y, size.width * 0.30, 8), Paint()..color = Color.lerp(const Color(0xFF4A3A2C), const Color(0xFF9C7A55), day)!);
  }

  void _bag(Canvas c, Size size) {
    final base = bagRect(size);
    final r = Rect.fromCenter(center: m.bagPos == Offset.zero ? base.center : m.bagPos, width: base.width, height: base.height);
    c.save();
    c.translate(r.center.dx, r.center.dy);
    c.rotate(m.bagTilt);
    final rr = Rect.fromCenter(center: Offset.zero, width: r.width, height: r.height);
    c.drawRRect(RRect.fromRectAndRadius(rr, const Radius.circular(6)), Paint()..color = const Color(0xFFD9534F));
    c.drawCircle(Offset(0, -rr.height * 0.05), rr.width * 0.22, Paint()..color = const Color(0xFFFFF4E0));
    c.drawCircle(Offset(-rr.width * 0.07, -rr.height * 0.07), rr.width * 0.05, Paint()..color = const Color(0xFF9B5E2E));
    c.drawCircle(Offset(rr.width * 0.07, -rr.height * 0.03), rr.width * 0.05, Paint()..color = const Color(0xFF9B5E2E));
    c.restore();
  }

  void _jug(Canvas c, Size size) {
    final base = jugRect(size);
    final r = Rect.fromCenter(center: m.jugPos == Offset.zero ? base.center : m.jugPos, width: base.width, height: base.height);
    c.save();
    c.translate(r.center.dx, r.center.dy);
    c.rotate(m.jugTilt);
    final rr = Rect.fromCenter(center: Offset.zero, width: r.width, height: r.height);
    c.drawRRect(RRect.fromRectAndRadius(rr, const Radius.circular(10)), Paint()..color = const Color(0xFFBFE3F7).withValues(alpha: 0.85));
    c.drawRect(Rect.fromLTWH(rr.left, rr.top + rr.height * 0.3, rr.width, rr.height * 0.7), Paint()..color = const Color(0xFF6FB3E0).withValues(alpha: 0.7));
    c.drawRect(Rect.fromCenter(center: Offset(0, rr.top - 4), width: rr.width * 0.4, height: 8), Paint()..color = const Color(0xFF3D7EAA));
    c.restore();
  }

  void _bed(Canvas c, WorldView v, double day) {
    final center = v.p(const V2(World.bedX, 1.2));
    c.drawOval(Rect.fromCenter(center: center, width: 30 * v.s, height: 7 * v.s), Paint()..color = const Color(0xFF6C8EAD));
    c.drawOval(Rect.fromCenter(center: center + Offset(0, -1.2 * v.s), width: 24 * v.s, height: 4 * v.s), Paint()..color = const Color(0xFF8FB0CC));
  }

  void _nest(Canvas c, WorldView v, double ageDays) {
    final fade = clampD((60 - ageDays) / 6, 0, 1);
    final center = v.p(const V2(World.nestX, 1));
    c.drawOval(Rect.fromCenter(center: center, width: 34 * v.s, height: 6 * v.s), Paint()..color = const Color(0xFFE7C9A9).withValues(alpha: fade));
  }

  bool get _dog => m.species == Species.dog;

  void _toiletBack(Canvas c, WorldView v, World w) {
    final l = v.p(const V2(World.toiletX - World.toiletHalfW, 0));
    final r = v.p(const V2(World.toiletX + World.toiletHalfW, 0));
    if (_dog) {
      c.drawRect(Rect.fromLTRB(l.dx, l.dy - 0.8 * v.s, r.dx, r.dy + 2), Paint()..color = const Color(0xFFE9F1F7));
      for (final waste in w.toilet) {
        _waste(c, v, waste, onFloor: false);
      }
      return;
    }
    final h = 4.5 * v.s;
    c.drawRect(Rect.fromLTRB(l.dx, l.dy - h, r.dx, l.dy), Paint()..color = const Color(0xFF3F8A8C));
    c.drawRect(Rect.fromLTRB(l.dx + 3, l.dy - h * 0.55, r.dx - 3, l.dy), Paint()..color = const Color(0xFFD8CBB0));
    for (final waste in w.toilet) {
      _waste(c, v, waste, onFloor: false, raised: h * 0.5);
    }
  }

  void _toiletFront(Canvas c, WorldView v, World w) {
    if (_dog) return;
    final l = v.p(const V2(World.toiletX - World.toiletHalfW, 0));
    final r = v.p(const V2(World.toiletX + World.toiletHalfW, 0));
    final h = 3.2 * v.s;
    c.drawRRect(RRect.fromLTRBR(l.dx - 2, l.dy - h, r.dx + 2, l.dy + 2, const Radius.circular(3)), Paint()..color = const Color(0xFF4FA3A5));
  }

  void _waste(Canvas c, WorldView v, Waste waste, {required bool onFloor, double raised = 0}) {
    final p = v.p(V2(waste.x, 0)) - Offset(0, raised);
    if (waste.kind == WasteKind.feces) {
      final paint = Paint()..color = const Color(0xFF5B3A1E);
      c.drawOval(Rect.fromCenter(center: p + Offset(0, -0.6 * v.s), width: 2.6 * v.s, height: 1.3 * v.s), paint);
      c.drawOval(Rect.fromCenter(center: p + Offset(0.5 * v.s, -1.4 * v.s), width: 1.8 * v.s, height: 1.0 * v.s), paint);
    } else if (onFloor || _dog) {
      c.drawOval(Rect.fromCenter(center: p + Offset(0, 0.3 * v.s), width: 7 * v.s, height: 1.4 * v.s),
          Paint()..color = const Color(0xFFE8D24A).withValues(alpha: 0.55));
    } else {
      c.drawOval(Rect.fromCenter(center: p, width: 2.4 * v.s, height: 1.2 * v.s), Paint()..color = const Color(0xFF9E978A));
    }
  }

  void _bowl(Canvas c, WorldView v, double x, double level, Color content, {required bool water}) {
    final p = v.p(V2(x, 0));
    final w = 9 * v.s, h = 2.8 * v.s;
    final bowl = Path()
      ..moveTo(p.dx - w / 2, p.dy - h)
      ..lineTo(p.dx + w / 2, p.dy - h)
      ..lineTo(p.dx + w * 0.38, p.dy)
      ..lineTo(p.dx - w * 0.38, p.dy)
      ..close();
    if (level > 0.005) {
      final fill = Rect.fromCenter(center: Offset(p.dx, p.dy - h - (water ? 0 : level * 0.8 * v.s)), width: w * 0.92, height: (water ? 1.0 : 1.6 + level * 1.4) * v.s);
      c.drawOval(fill, Paint()..color = content.withValues(alpha: water ? 0.4 + 0.5 * level : 1));
    }
    c.drawPath(bowl, Paint()..color = water ? const Color(0xFF2F5D8A) : const Color(0xFFB04A3C));
  }

  void _ball(Canvas c, WorldView v, Ball b) {
    final p = v.p(V2(b.x, b.y + Ball.r));
    c.drawCircle(p, Ball.r * v.s, Paint()..color = const Color(0xFFE53935));
    c.drawCircle(p + Offset(-Ball.r * 0.35 * v.s, -Ball.r * 0.35 * v.s), Ball.r * 0.3 * v.s, Paint()..color = Colors.white.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(covariant ScenePainter oldDelegate) => false;

  static double clampAngle(double a) => math.atan2(math.sin(a), math.cos(a));
}
