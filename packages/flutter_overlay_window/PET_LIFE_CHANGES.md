# 修改說明

來源：https://github.com/X-SLAYER/flutter_overlay_window （MIT，版本 1.0.2，commit d272e2c）

唯一的修改：`OverlayService.startForegroundWithTypes()`
- 原版 `startForeground(id, notification)` 在 Android 14+ 會套用 manifest 宣告的所有前景服務類型；
  我們宣告了 specialUse|microphone|camera，若使用者沒給麥克風或相機權限就會 SecurityException。
- 改成依目前已授權的權限組合類型；失敗時退回 specialUse。

其他新增（全部標了 `[Pet Life 新增]` / `[Pet Life 修改]`）：
- `OverlayService`：
  - `pet_overlay/touch`（BasicMessageChannel）：把每個觸控事件的螢幕座標（dp）送給 Dart。視窗一直跟著貓移動，只用視窗內座標會互相干擾。
  - `pet_overlay/window`（MethodChannel）：`metrics`（螢幕與系統列大小）、`place`（直接設定視窗位置／大小，dp，不做原版的邊界修正）、`haptic`（呼嚕震動 25 Hz、拍打、輕點）。
  - `onDestroy` 時通知懸浮引擎 `appIsPaused`，停止動畫與感測。
- `FlutterOverlayWindowPlugin`：`petCheckRuntime` / `petRequestRuntime`（麥克風、相機、通知權限）、`petOpenAppSettings`、`petSdkInt`。
