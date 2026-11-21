import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

/// 「手機螢幕是一扇窗」的相機。
///
/// 世界座標（和 2D 模擬同一套單位）：x 向右、y 向上、地板 y = 0、z 往螢幕裡面。
/// 螢幕就是 z = 0 這個平面；眼睛在螢幕前方 [distance]。
///
/// 懸浮視窗平常只有貓那麼大、跟著貓移動。這裡的視錐永遠穿過「這個小視窗在螢幕上的那一塊」
/// （off-axis 投影），所以小視窗和全螢幕看到的貓位置完全一樣，2D 的視窗與觸控邏輯不用改。
/// 之後做視差（手機一歪就看到側面）只要移動眼睛，螢幕平面上的東西不會跑位。
class WindowCamera extends fs.Camera {
  final OffAxisProjection lens = OffAxisProjection();
  vm.Vector3 eye = vm.Vector3(0, 0, -1000);

  double _s = 1, _floorY = 0;

  /// 每個世界單位在螢幕上幾 dp
  double get s => _s;

  /// 地板在螢幕上的 y（dp）
  double get floorY => _floorY;

  /// 眼睛到螢幕平面的距離（世界單位）
  double get distance => lens.d;

  @override
  vm.Vector3 get position => eye;

  @override
  vm.Vector3 get forward => vm.Vector3(0, 0, 1);

  @override
  vm.Vector3 get up => vm.Vector3(0, 1, 0);

  @override
  fs.CameraProjection get projection => lens;

  @override
  vm.Matrix4 getViewMatrix() => vm.Matrix4.translationValues(-eye.x, -eye.y, -eye.z);

  /// [screen]：整個螢幕（dp）；[window]：這次要畫的那一塊（dp，懸浮視窗在螢幕上的位置）；
  /// [fovY]：螢幕高度對眼睛的張角（手機拿在 30 cm 外約 28°）；[eyeShift]：眼睛偏移（世界單位）。
  void frame({
    required ui.Size screen,
    required double floorY,
    required double s,
    required ui.Rect window,
    double fovY = 30 * math.pi / 180,
    vm.Vector2? eyeShift,
  }) {
    _s = s;
    _floorY = floorY;
    final dist = screen.height / s / 2 / math.tan(fovY / 2);
    eye = vm.Vector3(
      screen.width / 2 / s + (eyeShift?.x ?? 0),
      (floorY - screen.height / 2) / s + (eyeShift?.y ?? 0),
      -dist,
    );
    lens
      ..d = dist
      ..left = window.left / s - eye.x
      ..right = window.right / s - eye.x
      ..top = (floorY - window.top) / s - eye.y
      ..bottom = (floorY - window.bottom) / s - eye.y
      ..near = math.max(1.0, dist - 400)
      ..far = dist + 800;
  }

  /// 世界座標 → 螢幕座標（dp）：眼睛到該點的直線和螢幕平面（z = 0）的交點
  ui.Offset toScreen(vm.Vector3 p) {
    final t = -eye.z / (p.z - eye.z);
    final x = eye.x + (p.x - eye.x) * t, y = eye.y + (p.y - eye.y) * t;
    return ui.Offset(x * _s, _floorY - y * _s);
  }

  /// 該深度的東西在螢幕上的縮放倍率（z = 0 時為 1）
  double depthScale(vm.Vector3 p) => -eye.z / (p.z - eye.z);
}

/// 穿過螢幕上一個矩形的透視投影（view space 裡，距離 [d] 的平面上的 [left]..[right]、[bottom]..[top]）。
/// 深度用一般（非反轉）寫法；flutter_scene 會自己把自訂投影的深度列反轉（render/depth_raster.dart）。
class OffAxisProjection extends fs.CameraProjection {
  double left = -1, right = 1, bottom = -1, top = 1, d = 1;
  double near = 0.1, far = 1000;

  @override
  vm.Matrix4 getProjectionMatrix(double aspectRatio, {vm.Vector2? jitter}) =>
      offAxisMatrix(left: left, right: right, bottom: bottom, top: top, d: d, near: near, far: far, jitter: jitter);
}

/// clip = M · view；w = view z（眼睛往 +z 看），和 flutter_scene 內建透視矩陣同一個慣例。
vm.Matrix4 offAxisMatrix({
  required double left,
  required double right,
  required double bottom,
  required double top,
  required double d,
  required double near,
  required double far,
  vm.Vector2? jitter,
}) {
  final a = far / (far - near), b = -far * near / (far - near);
  // vector_math 的 Matrix4 建構子是「一欄一欄」填
  return vm.Matrix4(
    2 * d / (right - left), 0, 0, 0, //
    0, 2 * d / (top - bottom), 0, 0, //
    -(right + left) / (right - left) + (jitter?.x ?? 0), -(top + bottom) / (top - bottom) + (jitter?.y ?? 0), a, 1, //
    0, 0, b, 0,
  );
}
