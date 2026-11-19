import 'package:flutter/services.dart';

import '../sim/util.dart';

/// 執行期權限（麥克風、相機、通知）。走 packages/flutter_overlay_window 裡加的方法，
/// 不另外引入權限套件。
class Perms {
  static const _ch = MethodChannel('x-slayer/overlay_channel');
  static const mic = 'android.permission.RECORD_AUDIO';
  static const camera = 'android.permission.CAMERA';
  static const notifications = 'android.permission.POST_NOTIFICATIONS';

  static Future<int> sdk() async {
    try {
      return await _ch.invokeMethod<int>('petSdkInt') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> granted(String perm) async {
    try {
      final m = await _ch.invokeMapMethod<String, bool>('petCheckRuntime', {'perms': [perm]});
      return m?[perm] ?? false;
    } catch (e) {
      petLog('perm check failed $e');
      return false;
    }
  }

  /// 會跳出系統詢問框；回傳是否已允許
  static Future<bool> request(String perm) async {
    try {
      final m = await _ch.invokeMapMethod<String, bool>('petRequestRuntime', {'perms': [perm]});
      final ok = m?[perm] ?? false;
      petLog('perm $perm -> $ok');
      return ok;
    } catch (e) {
      petLog('perm request failed $e');
      return false;
    }
  }

  static Future<void> openAppSettings() async {
    try {
      await _ch.invokeMethod<bool>('petOpenAppSettings');
    } catch (_) {}
  }
}
