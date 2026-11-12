import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

void main() => runApp(const MaterialApp(home: HomePage()));

/// 浮在其他 App 上面的部分從這裡執行（獨立的 Flutter engine）
@pragma('vm:entry-point')
void overlayMain() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Material(
      color: Colors.transparent,
      child: Center(child: PetSprite(size: 160)),
    ),
  ));
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _show() async {
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      final granted = await FlutterOverlayWindow.requestPermission();
      if (granted != true) return;
    }
    await FlutterOverlayWindow.showOverlay(
      width: 400,
      height: 400,
      enableDrag: true,
      flag: OverlayFlag.defaultFlag,
      positionGravity: PositionGravity.none,
      overlayTitle: '寵物運作中',
      overlayContent: '點這裡回到 App',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pet Overlay MVP')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PetSprite(size: 160),
            const SizedBox(height: 24),
            FilledButton(onPressed: _show, child: const Text('讓寵物浮在其他 App 上')),
            TextButton(
              onPressed: () => FlutterOverlayWindow.closeOverlay(),
              child: const Text('收起寵物'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 佔位用的寵物；之後換成 AI 生成的逐格圖
class PetSprite extends StatefulWidget {
  const PetSprite({super.key, this.size = 160});
  final double size;

  @override
  State<PetSprite> createState() => _PetSpriteState();
}

class _PetSpriteState extends State<PetSprite>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => CustomPaint(
        size: Size.square(widget.size),
        painter: _PetPainter(_c.value),
      ),
    );
  }
}

class _PetPainter extends CustomPainter {
  _PetPainter(this.t);
  final double t; // 動畫進度 0..1

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final bob = math.sin(t * 2 * math.pi) * w * 0.03; // 呼吸起伏
    final tail = math.sin(t * 4 * math.pi) * 0.5; // 尾巴擺動
    final blink = t > 0.92 ? 0.15 : 1.0; // 每輪眨一次眼
    final body = Paint()..color = const Color(0xFFF2A65A);
    final dark = Paint()..color = const Color(0xFF3B2A20);

    canvas.save();
    canvas.translate(0, bob);

    // 尾巴
    canvas.save();
    canvas.translate(w * 0.72, w * 0.70);
    canvas.rotate(-0.6 + tail);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, -w * 0.04, w * 0.25, w * 0.08),
        Radius.circular(w * 0.04),
      ),
      body,
    );
    canvas.restore();

    // 身體、頭
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, w * 0.70), width: w * 0.55, height: w * 0.40),
      body,
    );
    canvas.drawCircle(Offset(w * 0.5, w * 0.42), w * 0.22, body);

    // 耳朵、眼睛（左右對稱）
    for (final dx in [-1.0, 1.0]) {
      final ear = Path()
        ..moveTo(w * (0.5 + dx * 0.20), w * 0.34)
        ..lineTo(w * (0.5 + dx * 0.17), w * 0.14)
        ..lineTo(w * (0.5 + dx * 0.05), w * 0.24)
        ..close();
      canvas.drawPath(ear, body);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * (0.5 + dx * 0.08), w * 0.42),
          width: w * 0.05,
          height: w * 0.07 * blink,
        ),
        dark,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PetPainter old) => old.t != t;
}
