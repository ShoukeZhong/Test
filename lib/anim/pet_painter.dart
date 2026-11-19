import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../sim/species.dart';
import '../sim/util.dart';
import 'rig.dart';

class Coat {
  const Coat(this.name, this.base, this.dark, this.light, {this.tabby = false});
  final String name;
  final Color base, dark, light;
  final bool tabby;
}

const List<Coat> catCoats = [
  Coat('橘虎斑', Color(0xFFF2A65A), Color(0xFFC77A33), Color(0xFFFBE3C6), tabby: true),
  Coat('灰', Color(0xFF9AA0A6), Color(0xFF6B7178), Color(0xFFE6E8EA)),
  Coat('黑', Color(0xFF2E2E33), Color(0xFF17171A), Color(0xFF5A5B60)),
  Coat('白', Color(0xFFF2EEE6), Color(0xFFD5CBBB), Color(0xFFFFFFFF)),
];
const List<Coat> dogCoats = [
  Coat('淺棕', Color(0xFFD9A066), Color(0xFFA8733C), Color(0xFFF5E1C4)),
  Coat('深棕', Color(0xFF8B5A3C), Color(0xFF5E3B26), Color(0xFFC79B7C)),
  Coat('黑', Color(0xFF2E2E33), Color(0xFF17171A), Color(0xFF8A7A6A)),
  Coat('白', Color(0xFFF2EEE6), Color(0xFFD5CBBB), Color(0xFFFFFFFF)),
];
List<Coat> coatsOf(Species s) => s == Species.dog ? dogCoats : catCoats;

/// 世界座標 → 螢幕座標
class WorldView {
  WorldView(this.size) : s = size.width / 100, floorY = size.height * 0.80;
  final Size size;
  final double s;
  final double floorY;
  Offset p(V2 v) => Offset(v.x * s, floorY - v.y * s);
  V2 w(Offset o) => V2(o.dx / s, (floorY - o.dy) / s);
}

/// 把骨架畫成貓狗。全部用路徑繪製，沒有圖片素材。
class PetPainterKit {
  static void paint(Canvas c, WorldView v, RigFrame r, Coat coat, {double alpha = 1, double dim = 0, double ageDays = 400}) {
    final s = v.s;
    final f = r.facing;
    Color tone(Color col) {
      var out = Color.lerp(col, const Color(0xFFB9B9B9), r.greying * 0.5)!;
      if (dim > 0) out = Color.lerp(out, const Color(0xFF6E6E6E), dim)!;
      return out.withValues(alpha: alpha);
    }

    final base = tone(coat.base), dark = tone(coat.dark), light = tone(coat.light);
    final farCol = Color.lerp(base, dark, 0.4)!;

    // 影子
    final mid = V2.lerp(r.hip, r.shoulder, 0.5);
    c.drawOval(
      Rect.fromCenter(center: v.p(V2(mid.x, 0)), width: r.L * 1.1 * s, height: math.max(2.0, r.L * 0.12 * s)),
      Paint()..color = Colors.black.withValues(alpha: 0.13 * alpha),
    );

    // 尾巴（在身體後面）
    _tail(c, v, r, base, dark);

    // 遠側的腳
    for (final l in r.legs.where((l) => l.far)) {
      _leg(c, v, l, r, farCol);
    }

    // 身體：沿脊椎曲線取樣，組成平滑外框
    final body = Path();
    final top = <Offset>[], bottom = <Offset>[];
    const n = 14;
    for (var i = 0; i <= n; i++) {
      final u = i / n;
      final a = V2.lerp(r.hip, r.spineCtrl, u), b = V2.lerp(r.spineCtrl, r.shoulder, u);
      final pt = V2.lerp(a, b, u);
      final d = (V2.lerp(r.spineCtrl, r.shoulder, u) - V2.lerp(r.hip, r.spineCtrl, u)).normalized();
      var nrm = V2(-d.y, d.x);
      if (nrm.y < 0) nrm = nrm * -1;
      final rad = lerpD(r.torsoT * 0.56, r.torsoT * 0.48, u) * (1 + 0.1 * math.sin(math.pi * u)) * r.chest;
      top.add(v.p(pt + nrm * rad));
      bottom.add(v.p(pt - nrm * (rad * 1.05)));
    }
    body.moveTo(top.first.dx, top.first.dy);
    for (var i = 1; i < top.length; i++) {
      final p0 = top[i - 1], p1 = top[i];
      body.quadraticBezierTo(p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    }
    body.lineTo(top.last.dx, top.last.dy);
    final endCap = v.p(r.shoulder + V2(f * r.torsoT * 0.45, 0));
    body.quadraticBezierTo(endCap.dx, endCap.dy, bottom.last.dx, bottom.last.dy);
    for (var i = bottom.length - 2; i >= 0; i--) {
      final p0 = bottom[i + 1], p1 = bottom[i];
      body.quadraticBezierTo(p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    }
    final hipCap = v.p(r.hip + V2(-f * r.torsoT * 0.5, 0));
    body.quadraticBezierTo(hipCap.dx, hipCap.dy, top.first.dx, top.first.dy);
    body.close();
    final bounds = body.getBounds();
    c.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(bounds.topCenter, bounds.bottomCenter, [base, base, light], [0, 0.6, 1]),
    );
    if (coat.tabby) {
      final stripe = Paint()
        ..color = dark.withValues(alpha: 0.55 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.0, r.torsoT * 0.09 * s);
      for (final k in [3, 5, 7, 9, 11]) {
        final p = top[k];
        final q = Offset.lerp(top[k], bottom[k], 0.35)!;
        c.drawLine(p, q, stripe);
      }
    }

    // 脖子
    c.drawLine(
      v.p(r.shoulder + V2(0, r.torsoT * 0.15)),
      v.p(r.head - V2(0, r.headR * 0.3)),
      Paint()
        ..color = base
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r.torsoT * 0.62 * s,
    );

    // 近側的腳
    for (final l in r.legs.where((l) => !l.far)) {
      _leg(c, v, l, r, base);
    }

    _head(c, v, r, base, dark, light, alpha, ageDays);
  }

  static void _tail(Canvas c, WorldView v, RigFrame r, Color base, Color dark) {
    final pts = r.tail;
    for (var i = 0; i < pts.length - 1; i++) {
      final u = i / (pts.length - 1);
      final w = lerpD(r.tailW0, r.tailW1, u) * v.s;
      c.drawLine(
        v.p(pts[i]),
        v.p(pts[i + 1]),
        Paint()
          ..color = r.species == Species.cat && i >= pts.length - 3 ? Color.lerp(base, dark, 0.35)! : base
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.5, w),
      );
    }
  }

  static void _leg(Canvas c, WorldView v, LegGeom l, RigFrame r, Color col) {
    final s = v.s;
    final upper = r.torsoT * (l.front ? 0.34 : 0.42) * s;
    final lower = r.torsoT * 0.24 * s;
    final p = Paint()
      ..color = col
      ..strokeCap = StrokeCap.round;
    c.drawLine(v.p(l.joint), v.p(l.knee), p..strokeWidth = math.max(2.0, upper));
    c.drawLine(v.p(l.knee), v.p(l.foot), p..strokeWidth = math.max(1.5, lower));
    c.drawOval(
      Rect.fromCenter(center: v.p(l.foot + V2(r.facing * r.torsoT * 0.05, r.torsoT * 0.06)), width: lower * 1.6, height: lower * 1.0),
      Paint()..color = col,
    );
  }

  static void _head(Canvas c, WorldView v, RigFrame r, Color base, Color dark, Color light, double alpha, double ageDays) {
    final s = v.s;
    final R = r.headR * s;
    final center = v.p(r.head);
    final f = r.facing;
    final side = f >= 0 ? 1.0 : -1.0;
    final turn = r.headTurn;
    final isCat = r.species == Species.cat;

    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(-r.tilt * side);

    // 耳朵
    final earH = R * (isCat ? 0.85 : 0.75) * r.earScale;
    for (final k in [-1.0, 1.0]) {
      // 正面：左右對稱；側面：一前一後
      final px = lerpD(side * (k < 0 ? -0.3 : 0.3), k * 0.58, turn) * R;
      final back = r.earsBack * 0.9 + r.earTwitch * (k > 0 ? 1 : 0);
      c.save();
      c.translate(px, -R * 0.62);
      c.rotate(-side * back * (isCat ? 1 : 0.4) + (turn * k * 0.25));
      if (isCat) {
        final ear = Path()
          ..moveTo(-R * 0.3, R * 0.15)
          ..lineTo(0, -earH)
          ..lineTo(R * 0.3, R * 0.15)
          ..close();
        c.drawPath(ear, Paint()..color = k < 0 && turn < 0.5 ? Color.lerp(base, dark, 0.3)! : base);
        final inner = Path()
          ..moveTo(-R * 0.15, R * 0.05)
          ..lineTo(0, -earH * 0.65)
          ..lineTo(R * 0.15, R * 0.05)
          ..close();
        c.drawPath(inner, Paint()..color = const Color(0xFFE9A6A6).withValues(alpha: 0.8 * alpha));
      } else {
        c.drawOval(Rect.fromLTWH(-R * 0.2, 0, R * 0.42, earH * 1.3), Paint()..color = dark);
      }
      c.restore();
    }

    // 頭形
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: R * 2.1, height: R * 1.9), Paint()..color = base);

    // 口鼻：側面在前方，正面在中下
    final snoutLen = isCat ? 0.35 : 0.85;
    final muzzle = Offset(lerpD(side * R * (0.7 + snoutLen * 0.4), 0, turn), R * lerpD(0.28, 0.42, turn));
    final mw = R * lerpD(0.75 + snoutLen * 0.6, 0.95, turn), mh = R * (isCat ? 0.55 : 0.7);
    c.drawOval(Rect.fromCenter(center: muzzle, width: mw, height: mh), Paint()..color = isCat ? light : Color.lerp(base, light, 0.5)!);
    final nose = muzzle + Offset(lerpD(side * mw * 0.42, 0, turn), -mh * 0.2);
    final noseR = R * (isCat ? 0.1 : 0.16);
    c.drawPath(
      Path()
        ..moveTo(nose.dx - noseR, nose.dy - noseR * 0.5)
        ..lineTo(nose.dx + noseR, nose.dy - noseR * 0.5)
        ..lineTo(nose.dx, nose.dy + noseR * 0.7)
        ..close(),
      Paint()..color = (isCat ? const Color(0xFFD9787F) : const Color(0xFF231F20)).withValues(alpha: alpha),
    );
    if (r.mouth > 0.04) {
      final mo = nose + Offset(0, noseR * 1.4 + r.mouth * R * 0.12);
      c.drawOval(Rect.fromCenter(center: mo, width: R * 0.32, height: R * 0.32 * r.mouth + 1),
          Paint()..color = const Color(0xFF4A1F25).withValues(alpha: alpha));
      if (r.mouth > 0.12) {
        c.drawOval(Rect.fromCenter(center: mo + Offset(0, R * 0.05 * r.mouth), width: R * 0.18, height: R * 0.12 * r.mouth),
            Paint()..color = const Color(0xFFE88A93).withValues(alpha: alpha));
      }
    }
    if (isCat) {
      final wp = Paint()
        ..color = Colors.white.withValues(alpha: 0.55 * alpha)
        ..strokeWidth = 1;
      for (final k in [-1.0, 0.0, 1.0]) {
        c.drawLine(muzzle + Offset(side * R * 0.1, k * R * 0.06), muzzle + Offset(side * R * 0.9, k * R * 0.14 - R * 0.05), wp);
        if (turn > 0.4) {
          c.drawLine(muzzle - Offset(side * R * 0.1, -k * R * 0.06), muzzle - Offset(side * R * 0.9, -k * R * 0.14 + R * 0.05), wp);
        }
      }
    }

    // 眼睛：小時候藍灰色，之後轉成成年眼色〔查證：幼貓一開始都是藍灰色眼睛〕
    final irisAdult = isCat ? const Color(0xFFB7C24A) : const Color(0xFF6B4423);
    final iris = Color.lerp(const Color(0xFF7D93A8), irisAdult, clampD((ageDays - 42) / 60, 0, 1))!;
    final ew = R * 0.34, eh = R * 0.4;
    final eyeA = Offset(lerpD(side * R * 0.55, R * 0.42, turn), -R * 0.08);
    final eyeB = Offset(lerpD(side * R * 0.55, -R * 0.42, turn), -R * 0.08);
    for (final e in [(eyeA, 1.0), (eyeB, turn)]) {
      if (e.$2 < 0.05) continue;
      final pos = e.$1;
      final a = alpha * e.$2;
      if (r.eyeOpen < 0.12) {
        c.drawArc(Rect.fromCenter(center: pos, width: ew, height: eh * 0.5), 0.2, math.pi - 0.4, false,
            Paint()
              ..color = const Color(0xFF2A1A12).withValues(alpha: a)
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1.2, R * 0.06));
        continue;
      }
      final h = eh * r.eyeOpen;
      final rect = Rect.fromCenter(center: pos, width: ew, height: h);
      c.save();
      c.clipPath(Path()..addOval(rect));
      c.drawOval(rect, Paint()..color = iris.withValues(alpha: a));
      final g = Offset(r.gaze.x * side * ew * 0.18, -r.gaze.y * h * 0.15);
      final pupilRect = isCat
          ? Rect.fromCenter(center: pos + g, width: ew * 0.9 * r.pupil, height: eh * 0.92)
          : Rect.fromCenter(center: pos + g, width: ew * (0.4 + 0.3 * r.pupil), height: ew * (0.4 + 0.3 * r.pupil));
      c.drawOval(pupilRect, Paint()..color = const Color(0xFF111111).withValues(alpha: a));
      c.drawCircle(pos + g + Offset(-ew * 0.15, -h * 0.2), ew * 0.09, Paint()..color = Colors.white.withValues(alpha: 0.85 * a));
      c.restore();
      c.drawOval(rect,
          Paint()
            ..color = const Color(0xFF2A1A12).withValues(alpha: 0.6 * a)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, R * 0.04));
    }
    c.restore();
  }
}
