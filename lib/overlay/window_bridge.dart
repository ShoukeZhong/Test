import 'dart:async';

import 'package:flutter/services.dart';

import '../sim/util.dart';

/// 螢幕資訊（dp = Flutter 的邏輯像素）
class ScreenMetrics {
  const ScreenMetrics({
    required this.density,
    required this.width,
    required this.height,
    required this.statusBar,
    required this.navBar,
    required this.sdk,
  });
  final double density, width, height, statusBar, navBar;
  final int sdk;

  static const fallback = ScreenMetrics(density: 2.625, width: 411, height: 914, statusBar: 24, navBar: 48, sdk: 34);

  @override
  String toString() => 'density=$density screen=${width.toStringAsFixed(0)}x${height.toStringAsFixed(0)}dp '
      'status=${statusBar.toStringAsFixed(0)} nav=${navBar.toStringAsFixed(0)} sdk=$sdk';
}

/// 觸控事件（螢幕座標，dp）。action 與 Android MotionEvent.getActionMasked() 相同。
class RawTouch {
  RawTouch(this.action, this.x, this.y, this.timeMs, this.pointers);
  static const down = 0, up = 1, move = 2, cancel = 3, pointerDown = 5, pointerUp = 6;
  final int action;
  final double x, y;
  final int timeMs, pointers;
}

/// 跟 packages/flutter_overlay_window 裡加的原生程式溝通（見 PET_LIFE_CHANGES.md）
class WindowBridge {
  static const _window = MethodChannel('pet_overlay/window');
  static const _touch = BasicMessageChannel<Object?>('pet_overlay/touch', StandardMessageCodec());

  final StreamController<RawTouch> _touches = StreamController<RawTouch>.broadcast();
  Stream<RawTouch> get touches => _touches.stream;

  /// 原生端通知：視窗出現（true）／收起（false）
  final StreamController<bool> _shown = StreamController<bool>.broadcast();
  Stream<bool> get shown => _shown.stream;

  void listen() {
    _window.setMethodCallHandler((call) async {
      if (call.method == 'shown') _shown.add(true);
      if (call.method == 'hidden') _shown.add(false);
      return null;
    });
    _touch.setMessageHandler((msg) async {
      if (msg is List && msg.length >= 5) {
        _touches.add(RawTouch(
          (msg[0] as num).toInt(),
          (msg[1] as num).toDouble(),
          (msg[2] as num).toDouble(),
          (msg[3] as num).toInt(),
          (msg[4] as num).toInt(),
        ));
      }
      return null;
    });
  }

  Future<ScreenMetrics> metrics() async {
    try {
      final m = await _window.invokeMapMethod<String, Object?>('metrics');
      if (m == null) return ScreenMetrics.fallback;
      double d(String k) => (m[k] as num).toDouble();
      return ScreenMetrics(
        density: d('density'),
        width: d('screenW'),
        height: d('screenH'),
        statusBar: d('statusBar'),
        navBar: d('navBar'),
        sdk: (m['sdk'] as num).toInt(),
      );
    } catch (e) {
      petLog('metrics failed: $e');
      return ScreenMetrics.fallback;
    }
  }

  /// 視窗位置與大小（dp，左上角為原點）
  Future<bool> place(double x, double y, double w, double h) async {
    try {
      return await _window.invokeMethod<bool>('place', {'x': x, 'y': y, 'w': w, 'h': h}) ?? false;
    } catch (e) {
      petLog('place failed: $e');
      return false;
    }
  }

  /// purr_on / purr_off / swat / tick
  void haptic(String kind) {
    _window.invokeMethod<bool>('haptic', {'kind': kind}).catchError((Object e) {
      petLog('haptic failed: $e');
      return false;
    });
  }
}
