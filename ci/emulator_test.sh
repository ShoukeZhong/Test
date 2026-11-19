#!/usr/bin/env bash
# 模擬器實測（照真人操作順序）：
#  T1 沒權限 → 看到說明 → 按「去開啟權限」→ 設定頁 → 打開開關 → 返回 → 寵物自動出現
#  T2 關掉 App 再重開 → 不用按任何按鈕，寵物自動出現
#  T3 打開別的 App（系統設定）→ 寵物還浮在上面
set -u
OUT=ci-out
PKG=com.joker.pet_overlay
APK=build/app/outputs/flutter-apk/app-release.apk
mkdir -p "$OUT"
: > "$OUT/emulator_result.txt"
FAILED=0

log() { echo "[emu] $*" | tee -a "$OUT/emulator_steps.txt"; }
shot() { adb exec-out screencap -p > "$OUT/$1.png"; }
result() { echo "$1" | tee -a "$OUT/emulator_result.txt"; case "$1" in FAIL*) FAILED=1;; esac; }

# 這個 App 自己的浮動視窗在不在（SystemUI 也有 APPLICATION_OVERLAY，不能只看類型）
pet_up() {
  adb shell dumpsys window windows > "$OUT/dumpsys_$1.txt" 2>&1
  grep -A4 "u0 $PKG}" "$OUT/dumpsys_$1.txt" | grep -q "ty=APPLICATION_OVERLAY"
}

tap_label() {  # 從畫面上找文字並點下去
  local xy=""
  for i in 1 2 3 4; do
    adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1
    adb pull /sdcard/ui.xml "$OUT/ui_$2.xml" > /dev/null 2>&1
    xy=$(python3 ci/find_tap.py "$OUT/ui_$2.xml" "$1") && break
    xy=""
    sleep 4
  done
  [ -n "$xy" ] || return 1
  log "tap '$1' at $xy"
  adb shell input tap $xy
}

launch() { adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1; }

adb wait-for-device
log "install"
adb install -r "$APK" >> "$OUT/emulator_steps.txt" 2>&1 || { result "FAIL install"; exit 1; }
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null || true
adb shell appops set "$PKG" SYSTEM_ALERT_WINDOW deny
adb logcat -c

# ---- T1 ----
log "T1 launch without permission"
launch; sleep 20; shot 1_no_permission
if tap_label "去開啟權限" t1; then
  sleep 6; shot 2_settings_page
  adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1
  adb pull /sdcard/ui.xml "$OUT/ui_settings.xml" > /dev/null 2>&1
  grep -q "Pet Overlay" "$OUT/ui_settings.xml" && log "settings page shows 'Pet Overlay'" || log "WARN settings page has no 'Pet Overlay' text"
  log "simulate user switching the toggle on"
  adb shell appops set "$PKG" SYSTEM_ALERT_WINDOW allow
  adb shell input keyevent KEYCODE_BACK; sleep 10; shot 3_back_in_app
  if pet_up t1; then result "PASS T1 permission flow -> pet appears automatically"; else result "FAIL T1 pet did not appear after granting"; fi
else
  shot 1b_button_not_found
  result "FAIL T1 button '去開啟權限' not found"
  adb shell appops set "$PKG" SYSTEM_ALERT_WINDOW allow
fi

# ---- T2 ----
log "T2 force-stop and relaunch"
adb shell am force-stop "$PKG"; sleep 3
pet_up t2_before && log "WARN overlay still up after force-stop" || log "overlay gone after force-stop"
launch; sleep 15; shot 4_relaunch
if pet_up t2; then result "PASS T2 relaunch -> pet appears without tapping"; else result "FAIL T2 pet did not auto-appear on launch"; fi
adb shell input keyevent KEYCODE_HOME; sleep 5; shot 5_home_with_pet

# ---- T3 ----
log "T3 open another app"
adb shell am start -a android.settings.SETTINGS > /dev/null 2>&1; sleep 6; shot 6_over_other_app
if pet_up t3; then result "PASS T3 pet floats over another app"; else result "FAIL T3 pet not over other app"; fi

adb logcat -d > "$OUT/logcat.txt" 2>&1
exit $FAILED
