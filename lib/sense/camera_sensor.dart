import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../sim/stimuli.dart';
import '../sim/util.dart';

/// 前鏡頭 → 亮度、動作量、動作位置。只讀亮度（Y）平面做粗略網格比較，影像不存、不上傳。
class CameraSensor {
  CameraSensor(this.stim);

  final Stimuli stim;
  CameraController? _c;
  int _lastMs = 0;
  Float64List? _prev;
  int _sensorOrientation = 270;
  bool running = false;
  static const int _gw = 16, _gh = 12;

  Future<bool> start() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        petLog('camera none');
        return false;
      }
      final cam = cams.firstWhere((d) => d.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      _sensorOrientation = cam.sensorOrientation;
      final c = CameraController(cam, ResolutionPreset.low, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await c.initialize();
      await c.startImageStream(_onImage);
      _c = c;
      running = true;
      stim.cameraOn = true;
      petLog('camera on (orientation $_sensorOrientation)');
      return true;
    } catch (e) {
      petLog('camera unavailable: $e');
      return false;
    }
  }

  void _onImage(CameraImage img) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMs < 110) return; // 約 9 fps 就夠，省電
    _lastMs = now;
    if (img.planes.isEmpty) return;
    final plane = img.planes[0];
    final bytes = plane.bytes;
    final w = img.width, h = img.height;
    final stride = plane.bytesPerRow;
    final grid = Float64List(_gw * _gh);
    var total = 0.0;
    for (var gy = 0; gy < _gh; gy++) {
      for (var gx = 0; gx < _gw; gx++) {
        var sum = 0.0;
        var cnt = 0;
        final x0 = gx * w ~/ _gw, x1 = (gx + 1) * w ~/ _gw;
        final y0 = gy * h ~/ _gh, y1 = (gy + 1) * h ~/ _gh;
        for (var y = y0; y < y1; y += 4) {
          final row = y * stride;
          for (var x = x0; x < x1; x += 4) {
            final i = row + x;
            if (i < bytes.length) {
              sum += bytes[i];
              cnt++;
            }
          }
        }
        final avg = cnt == 0 ? 0.0 : sum / cnt;
        grid[gy * _gw + gx] = avg;
        total += avg;
      }
    }
    stim.brightness = clampD(total / (_gw * _gh) / 255 * 1.3, 0, 1);
    final prev = _prev;
    _prev = grid;
    if (prev == null) return;
    var diffSum = 0.0, wx = 0.0, wy = 0.0;
    for (var i = 0; i < grid.length; i++) {
      final d = (grid[i] - prev[i]).abs();
      if (d < 6) continue; // 雜訊
      diffSum += d;
      wx += d * (i % _gw);
      wy += d * (i ~/ _gw);
    }
    final motion = clampD(diffSum / (grid.length * 40), 0, 1);
    if (motion > 0.6 && stim.motion < 0.25) stim.motionBurst = true;
    stim.motion = lerpD(stim.motion, motion, 0.5);
    if (diffSum > 0) {
      final cx = wx / diffSum / (_gw - 1), cy = wy / diffSum / (_gh - 1);
      // 直拿手機時，感光元件轉了 90°／270°：影像的「列」對應螢幕的左右。〔未在實機驗證方向〕
      final sx = (_sensorOrientation == 90 || _sensorOrientation == 270) ? 1 - cy : 1 - cx;
      stim.motionX = lerpD(stim.motionX, clampD(sx, 0, 1), 0.4);
    }
  }

  Future<void> stop() async {
    final c = _c;
    _c = null;
    running = false;
    stim.cameraOn = false;
    if (c != null) {
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } catch (_) {}
      await c.dispose();
    }
    _prev = null;
  }

  double get debugMotion => math.min(1.0, stim.motion);
}
