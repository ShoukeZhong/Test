#!/usr/bin/env bash
# 模擬器實測（照真人操作順序）：
#  T1 第一次開 → 設定頁 → 按「讓牠出生」→ 進入寵物世界、模擬開始跑
#  T2 畫面是連續動畫：相隔 0.5 秒的兩張截圖不一樣，而且看得到寵物
#  T3 用手指撫摸寵物 → 判定為撫摸、進入「被摸」行為
#  T4 在地板上滑手指 → 判定為逗貓的手指
#  T5 關掉再開 → 不用重新設定，並補算關掉期間的時間
#  （模擬器沒有真的鏡頭和麥克風，T6 只記錄感測器狀態，不判定成敗）
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
launch() { adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1; }
logs() { adb logcat -d -s flutter:I > "$OUT/logcat_flutter.txt" 2>&1; }
haslog() { logs; grep -q "$1" "$OUT/logcat_flutter.txt"; }

tap_label() {  # 從畫面上找文字並點下去
  local xy=""
  for i in 1 2 3 4 5; do
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

pet_xy() {  # 從 logcat 最後一行 tick 取出寵物在螢幕上的位置（實體像素）
  logs
  grep -o 'screen=[0-9]*,[0-9]*' "$OUT/logcat_flutter.txt" | tail -1 | sed 's/screen=//; s/,/ /'
}

adb wait-for-device
log "install"
adb install -r "$APK" >> "$OUT/emulator_steps.txt" 2>&1 || { result "FAIL install"; exit 1; }
for p in CAMERA RECORD_AUDIO POST_NOTIFICATIONS; do adb shell pm grant "$PKG" android.permission.$p 2>/dev/null || true; done
adb logcat -c

# ---- T1 ----
log "T1 first launch -> setup -> birth"
launch; sleep 20; shot 1_setup
if tap_label "讓牠出生" t1; then
  sleep 12; shot 2_world
  if haslog "\[pet\] tick"; then result "PASS T1 birth -> world simulation running"; else result "FAIL T1 no simulation ticks after birth"; fi
else
  result "FAIL T1 button '讓牠出生' not found"
fi

# ---- T2 ----
log "T2 continuous animation"
shot 3a; sleep 0.5; shot 3b
diff=$(python3 ci/frame_diff.py "$OUT/3a.png" "$OUT/3b.png")
log "changed pixels between frames: $diff"
if [ "${diff:-0}" -ge 15 ]; then result "PASS T2 frames keep changing ($diff px)"; else result "FAIL T2 picture looks frozen ($diff px)"; fi
if python3 ci/pet_visible.py "$OUT/3a.png" 120 > "$OUT/pixels_3a.txt"; then result "PASS T2 pet visible ($(cat "$OUT/pixels_3a.txt") px)"; else result "FAIL T2 pet not visible ($(cat "$OUT/pixels_3a.txt") px)"; fi

# ---- T3 ----
log "T3 stroke the pet"
sleep 4
read -r PX PY <<< "$(pet_xy)"
log "pet at $PX,$PY"
if [ -n "${PX:-}" ]; then
  for i in 1 2 3 4; do adb shell input swipe $((PX - 45)) "$PY" $((PX + 45)) "$PY" 500; done
  sleep 1; shot 4_petting
  if haslog "touch stroke"; then result "PASS T3 stroke detected on pet"; else result "FAIL T3 stroke not detected"; fi
  if haslog "act=petted"; then result "PASS T3 pet reacted (petted)"; else result "FAIL T3 pet did not react"; fi
else
  result "FAIL T3 no pet position in log"
fi

# ---- T4 ----
log "T4 finger on the floor"
read -r PX PY <<< "$(pet_xy)"
W=$(adb shell wm size | grep -o '[0-9]*x[0-9]*' | tail -1 | cut -dx -f1)
H=$(adb shell wm size | grep -o '[0-9]*x[0-9]*' | tail -1 | cut -dx -f2)
FY=$((H * 82 / 100))
FX=$((W * 85 / 100)); [ "${PX:-0}" -gt $((W / 2)) ] && FX=$((W * 25 / 100))
adb shell input swipe "$FX" "$FY" $((FX + W / 10)) "$FY" 800
sleep 1
if haslog "touch down mode=finger"; then result "PASS T4 floor finger detected"; else result "FAIL T4 floor finger not detected"; fi

# ---- T5 ----
log "T5 close and reopen"
adb shell am force-stop "$PKG"; sleep 15
adb logcat -c
launch; sleep 15; shot 5_reopen
adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1
adb pull /sdcard/ui.xml "$OUT/ui_t5.xml" > /dev/null 2>&1
if grep -q "讓牠出生" "$OUT/ui_t5.xml"; then result "FAIL T5 setup page shown again (state lost)"; else result "PASS T5 pet kept after restart"; fi
if haslog "catch-up"; then result "PASS T5 offline time caught up"; else result "FAIL T5 no catch-up after restart"; fi

# ---- T6 ----
logs
grep -E "mic|camera" "$OUT/logcat_flutter.txt" | head -5 | sed 's/^/INFO T6 /' | tee -a "$OUT/emulator_result.txt"

adb logcat -d > "$OUT/logcat.txt" 2>&1
exit $FAILED
