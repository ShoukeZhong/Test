#!/usr/bin/env bash
# 模擬器實測：安裝 → 給浮動視窗權限 → 開 App → 按按鈕 → 回桌面 → 截圖 → 檢查 overlay 視窗
set -u
OUT=ci-out
PKG=com.joker.pet_overlay
APK=build/app/outputs/flutter-apk/app-release.apk
LABEL="讓寵物浮在其他 App 上"
mkdir -p "$OUT"

log() { echo "[emu] $*" | tee -a "$OUT/emulator_steps.txt"; }
fail() {
  log "FAIL: $*"
  echo "FAIL: $*" > "$OUT/emulator_result.txt"
  adb exec-out screencap -p > "$OUT/fail_screen.png" 2>/dev/null
  adb logcat -d > "$OUT/logcat.txt" 2>&1
  exit 1
}

adb wait-for-device
log "install"
adb install -r "$APK" >> "$OUT/emulator_steps.txt" 2>&1 || fail "adb install failed"
adb shell appops set "$PKG" SYSTEM_ALERT_WINDOW allow
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null || true
log "appops: $(adb shell appops get "$PKG" SYSTEM_ALERT_WINDOW)"

log "launch"
adb logcat -c
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 20
adb exec-out screencap -p > "$OUT/1_app.png"

btn=""
for i in 1 2 3 4; do
  adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1
  adb pull /sdcard/ui.xml "$OUT/ui.xml" > /dev/null 2>&1
  btn=$(python3 ci/find_tap.py "$OUT/ui.xml" "$LABEL") && break
  btn=""
  sleep 5
done
[ -n "$btn" ] || fail "button '$LABEL' not found in UI dump"
log "tap at $btn"
adb shell input tap $btn
sleep 10
adb exec-out screencap -p > "$OUT/2_after_tap.png"

adb shell input keyevent KEYCODE_HOME
sleep 6
adb exec-out screencap -p > "$OUT/3_home_with_pet.png"

adb shell dumpsys window windows > "$OUT/dumpsys_window.txt" 2>&1
adb logcat -d > "$OUT/logcat.txt" 2>&1
if grep -q "APPLICATION_OVERLAY" "$OUT/dumpsys_window.txt"; then
  log "overlay window present"
  echo "PASS" > "$OUT/emulator_result.txt"
else
  fail "no APPLICATION_OVERLAY window in dumpsys"
fi
