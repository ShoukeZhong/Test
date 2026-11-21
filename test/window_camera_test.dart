import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_overlay/three/window_camera.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// 用相機的 view × projection 把世界點投影到「懸浮視窗內的像素」，再換回螢幕 dp
Offset _project(WindowCamera cam, Rect win, vm.Vector3 p) {
  final clip = cam.lens.getProjectionMatrix(win.width / win.height).multiplied(cam.getViewMatrix()).transformed(vm.Vector4(p.x, p.y, p.z, 1));
  final nx = clip.x / clip.w, ny = clip.y / clip.w;
  return Offset(win.left + (nx + 1) / 2 * win.width, win.top + (1 - ny) / 2 * win.height);
}

void main() {
  const screen = Size(411, 914);
  const floorY = 914.0 - 48 - 2;
  const s = 2.0;
  final full = Rect.fromLTWH(0, 0, screen.width, screen.height);
  final small = Rect.fromLTWH(120, floorY + 6 - 45, 135, 45);

  test('螢幕平面（z=0）上的點：全螢幕和小視窗投影到同一個螢幕位置，也和 2D 的換算一致', () {
    final cam = WindowCamera();
    for (final p in [vm.Vector3(100, 0, 0), vm.Vector3(80, 12, 0), vm.Vector3(95.5, 3.2, 0)]) {
      final expect2d = Offset(p.x * s, floorY - p.y * s);
      cam.frame(screen: screen, floorY: floorY, s: s, window: full);
      final a = _project(cam, full, p);
      cam.frame(screen: screen, floorY: floorY, s: s, window: small);
      final b = _project(cam, small, p);
      expect((a - expect2d).distance, lessThan(1e-2), reason: 'full $a vs $expect2d');
      expect((b - expect2d).distance, lessThan(1e-2), reason: 'small $b vs $expect2d');
      expect((cam.toScreen(p) - expect2d).distance, lessThan(1e-3));
    }
  });

  test('比螢幕遠的點會往消失點靠、變小；toScreen 和矩陣投影一致', () {
    final cam = WindowCamera()..frame(screen: screen, floorY: floorY, s: s, window: small);
    final far = vm.Vector3(150, 10, 40), near = vm.Vector3(150, 10, -40);
    final pf = _project(cam, small, far), pn = _project(cam, small, near);
    expect((cam.toScreen(far) - pf).distance, lessThan(1e-2));
    expect((cam.toScreen(near) - pn).distance, lessThan(1e-2));
    final center = Offset(screen.width / 2, screen.height / 2);
    expect((pf - center).distance, lessThan((pn - center).distance));
    expect(cam.depthScale(far), lessThan(1));
    expect(cam.depthScale(near), greaterThan(1));
  });

  test('深度：近平面到遠平面在合理範圍、貓所在的深度不會被裁掉', () {
    final cam = WindowCamera()..frame(screen: screen, floorY: floorY, s: s, window: small);
    final m = cam.lens.getProjectionMatrix(3).multiplied(cam.getViewMatrix());
    for (final z in [-60.0, 0.0, 60.0]) {
      final c = m.transformed(vm.Vector4(100, 5, z, 1));
      final ndcZ = c.z / c.w;
      expect(ndcZ, inInclusiveRange(0.0, 1.0), reason: 'z=$z ndc=$ndcZ');
    }
  });
}
