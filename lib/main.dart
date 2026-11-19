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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool? _granted; // null = 還在檢查
  bool _userHidden = false; // 使用者按了「收起」就不要自動再叫出來
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 從設定頁開完權限回來時會觸發，寵物自動出現
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  /// 有權限就自動讓寵物出現；沒有就顯示開權限的說明
  Future<void> _sync() async {
    if (_busy) return;
    _busy = true;
    try {
      final granted = await FlutterOverlayWindow.isPermissionGranted();
      if (mounted) setState(() => _granted = granted);
      if (granted && !_userHidden && !await FlutterOverlayWindow.isActive()) {
        await _showPet();
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _showPet() async {
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

  Future<void> _askPermission() async {
    await FlutterOverlayWindow.requestPermission();
    await _sync();
  }

  Future<void> _toggle(bool show) async {
    _userHidden = !show;
    if (show) {
      if (!await FlutterOverlayWindow.isActive()) await _showPet();
    } else {
      await FlutterOverlayWindow.closeOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final granted = _granted;
    return Scaffold(
      appBar: AppBar(title: const Text('Pet Overlay')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: granted == null
              ? const CircularProgressIndicator()
              : granted
                  ? _readyView()
                  : _needPermissionView(),
        ),
      ),
    );
  }

  Widget _readyView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // App 裡不再畫一隻，避免跟浮動的那隻疊在一起
          const Text(
            '寵物已經浮在畫面上了。\n切到 LINE 或任何 App 都看得到，可以用手指拖著走。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => _toggle(true), child: const Text('顯示寵物')),
          TextButton(onPressed: () => _toggle(false), child: const Text('收起寵物')),
        ],
      );

  Widget _needPermissionView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PetSprite(size: 120),
          const SizedBox(height: 16),
          const Text('還差一步：開啟浮動權限',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text(
            '按下面的按鈕會打開「Display over other apps」清單。\n'
            '請往下找到「Pet Overlay」，打開它的開關，再按返回。\n\n'
            '不用打開 LINE 或其他 App——\n'
            '只要 Pet Overlay 有權限，寵物就會出現在所有 App 上面。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _askPermission, child: const Text('去開啟權限')),
          const SizedBox(height: 16),
          const Text(
            '小米／紅米手機：開了還是看不到的話，到 設定 → Apps → Pet Overlay → '
            'Other permissions，把「Display pop-up windows while running in the background」設成允許。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      );
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
