#!/usr/bin/env bash
# 模擬器實測（照真人操作）：
#  T1 開控制 App → 按「讓牠出現在螢幕上」→ 懸浮視窗出現
#  T2 回桌面 → 截圖看得到橘貓，而且畫面會動
#  T3 在貓背上滑 → 被摸（petted）
#  T4 輕點貓頭 → 戳一下（poke）
#  T5 長按貓 → 抱起來往上拖 → 放手 → 掉下來落地 → 視窗縮回小的
#  T6 打開別的 App（撥號）→ 貓還在上面
#  T7 打開麥克風開關（資訊）
#  T8 按「收起來」→ 懸浮視窗消失
#  T1–T7 用 2D 外觀跑（穩定的回歸測試）；最後才切 3D，避免 3D 拖垮模擬器時前面的結果也拿不到：
#  T9 切到「3D 實驗」→ 3D 引擎（flutter_scene／Flutter GPU）載入 → 桌面上看得到、會動 → 摸背 → 2D／3D 效能
#  （模擬器用 CPU 模擬 GPU，數字只當參考，實機才準）
set -u
OUT=ci-out
PKG=com.joker.pet_overlay
APK=build/app/outputs/flutter-apk/app-release.apk
mkdir -p "$OUT"
: > "$OUT/emulator_result.txt"
FAILED=0

# 每個 adb 指令都有時限：模擬器卡住時測試要能結束、把已經拿到的結果送出去
adb() { timeout "${ADB_T:-40}" command adb "$@"; }
log() { echo "[emu] $*" | tee -a "$OUT/emulator_steps.txt"; }
shot() { adb exec-out screencap -p > "$OUT/$1.png"; }
result() { echo "$1" | tee -a "$OUT/emulator_result.txt"; case "$1" in FAIL*) FAILED=1;; esac; }
launch() { adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1; }
# logcat 從頭到尾在背景寫到檔案（模擬器當掉也留得下紀錄）；讀紀錄不用再呼叫 adb
plog() { grep -a '\[pet\]' "$OUT/logcat_live.txt" 2>/dev/null; }

# 這個 App 自己的浮動視窗在不在（SystemUI 也有 APPLICATION_OVERLAY，不能只看類型）
pet_up() {
  adb shell dumpsys window windows > "$OUT/dumpsys_$1.txt" 2>&1
  grep -A4 "u0 $PKG}" "$OUT/dumpsys_$1.txt" | grep -q "ty=APPLICATION_OVERLAY"
}

# CI 模擬器偶爾會跳「Pixel Launcher isn't responding」之類的系統對話框，擋住畫面：按「Wait」關掉
dismiss_dialogs() {
  adb shell uiautomator dump /sdcard/ui_d.xml > /dev/null 2>&1
  adb pull /sdcard/ui_d.xml "$OUT/ui_dialog.xml" > /dev/null 2>&1
  if grep -qE "responding|keeps stopping|has stopped" "$OUT/ui_dialog.xml" 2>/dev/null; then
    local xy
    xy=$(python3 ci/find_tap.py "$OUT/ui_dialog.xml" "Wait") || xy=$(python3 ci/find_tap.py "$OUT/ui_dialog.xml" "Close app") || xy=""
    if [ -n "$xy" ]; then
      log "dismiss system dialog at $xy ($(grep -oE 'text="[^"]*(responding|stopping|stopped)[^"]*"' "$OUT/ui_dialog.xml" | head -1))"
      adb shell input tap $xy
      sleep 2
    fi
  fi
}

tap_label() {  # 從畫面上找文字並點下去
  local xy=""
  for i in 1 2 3 4; do
    dismiss_dialogs
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

# 截圖裡真的看得到橘貓；輸出「像素數 重心x 重心y」
pet_seen() { python3 ci/pet_visible.py "$OUT/$1.png" > "$OUT/pixels_$1.txt"; }
centroid_y() { awk '{print $3}' "$OUT/pixels_$1.txt"; }

wait_log() {  # wait_log 'pattern' 秒數
  for i in $(seq 1 "$2"); do
    plog | grep -q "$1" && return 0
    sleep 1
  done
  return 1
}

# 等貓停下來（vx≈0），回傳最新一行 tick 紀錄
still_line() {
  local line=""
  for i in $(seq 1 40); do
    line=$(plog | grep '\] tick ' | tail -1)
    local vx=$(echo "$line" | grep -oE 'vx=-?[0-9.]+' | cut -d= -f2)
    local mode=$(echo "$line" | grep -oE 'mode=[a-z]+' | cut -d= -f2)
    if [ -n "$vx" ] && [ "$mode" = "ground" ] && awk "BEGIN{exit !($vx < 0.5 && $vx > -0.5)}"; then
      break
    fi
    sleep 1
  done
  echo "$line" >> "$OUT/emulator_steps.txt"
  echo "$line"
}
# 從 tick 紀錄取出身體部位的實體像素座標 "X Y"
xy_of() { echo "$2" | grep -oE "$1=-?[0-9]+,-?[0-9]+" | head -1 | cut -d= -f2 | tr ',' ' '; }

command adb wait-for-device
log "install"
ADB_T=240 adb install -r "$APK" >> "$OUT/emulator_steps.txt" 2>&1 || { result "FAIL install"; exit 1; }
for p in POST_NOTIFICATIONS RECORD_AUDIO CAMERA; do adb shell pm grant "$PKG" android.permission.$p 2>/dev/null || true; done
adb shell appops set "$PKG" SYSTEM_ALERT_WINDOW allow
adb shell settings put global hide_error_dialogs 1 2>/dev/null || true
adb shell input keyevent KEYCODE_WAKEUP; adb shell wm dismiss-keyguard 2>/dev/null || true
sleep 20   # 讓桌面程式先穩定下來（大螢幕的模擬器開機後常常還在忙）
dismiss_dialogs
adb shell wm size >> "$OUT/emulator_steps.txt"; adb shell wm density >> "$OUT/emulator_steps.txt"
SIZE=$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -1)
SW=${SIZE%x*}; SH=${SIZE#*x}
log "screen ${SW}x${SH}"
adb shell input 2>&1 | grep -iE "motionevent|draganddrop" >> "$OUT/emulator_steps.txt" || true
adb logcat -c
command adb logcat -v time > "$OUT/logcat_live.txt" 2>&1 &
LOGCAT_PID=$!

# ---- T1 ----
log "T1 launch control app"
launch; sleep 15; shot 1_control
tap_label "2D 手繪" t1look || log "look switch not found (stays default)"
sleep 1
if tap_label "讓牠出現在螢幕上" t1; then
  if wait_log 'window small ready' 25 && pet_up t1; then result "PASS T1 overlay shown"; else result "FAIL T1 overlay not shown"; fi
else
  result "FAIL T1 button not found"
fi
sleep 3; shot 2_after_show


# ---- T2 ----
log "T2 home screen"
adb shell input keyevent KEYCODE_HOME; sleep 4; dismiss_dialogs; sleep 2; shot 3_home_a; sleep 6; shot 4_home_b
diff=$(python3 ci/frame_diff.py "$OUT/3_home_a.png" "$OUT/4_home_b.png")
log "frame diff home a/b = $diff px"
if pet_seen 3_home_a && pet_up t2; then
  if [ "$diff" -ge 15 ]; then result "PASS T2 cat visible over launcher and animating ($(cat $OUT/pixels_3_home_a.txt))"; else result "FAIL T2 cat visible but frozen (diff=$diff)"; fi
else
  result "FAIL T2 cat not visible over launcher ($(cat $OUT/pixels_3_home_a.txt))"
fi

# ---- T3 ----
# 在背上滑三下；只看這次之後的紀錄（T9 會在 3D 再做一次）
stroke_test() {  # stroke_test 名稱 截圖名
  dismiss_dialogs
  local line xy X Y hx DIR D n0
  line=$(still_line)
  xy=$(xy_of back "$line")
  [ -n "$xy" ] || { result "FAIL $1 no position log"; return; }
  set -- "$1" "$2" $xy; X=$3; Y=$4
  hx=$(xy_of head "$line" | cut -d' ' -f1)
  # 從背中間往頭的方向滑，至少 80 px（≈30 dp）：太短太慢的滑動會被當成長按、把貓抱起來
  DIR=1; [ "$hx" -lt "$X" ] && DIR=-1
  D=$(( (hx > X ? hx - X : X - hx) * 2 )); [ "$D" -lt 80 ] && D=80
  log "$1 back at $X,$Y swipe to $((X + DIR * D)) ($(echo "$line" | grep -oE 'look=[0-9a-z]+'))"
  n0=$(plog | wc -l)
  for k in 1 2 3; do adb shell input swipe $X $Y $((X + DIR * D)) $Y 400; sleep 0.3; done
  sleep 1; shot "$2"
  plog | tail -n +$((n0 + 1)) > "$OUT/logcat_$1.txt"
  if grep -q 'touch stroke' "$OUT/logcat_$1.txt" && grep -q 'act=petted' "$OUT/logcat_$1.txt"; then
    result "PASS $1 stroke -> petted ($(grep -oE 'touch stroke region=[a-z]+' "$OUT/logcat_$1.txt" | head -1))"
  else
    result "FAIL $1 stroke not detected"
  fi
}
log "T3 stroke the back"
stroke_test T3 5_stroke

# ---- T4 ----
log "T4 poke the head"
sleep 3
xy=$(xy_of head "$(still_line)")
if [ -n "$xy" ]; then
  set -- $xy
  adb shell input tap $1 $2; sleep 1
  if wait_log 'touch poke' 5; then result "PASS T4 tap -> poke"; else result "FAIL T4 poke not detected"; fi
else
  result "FAIL T4 no position log"
fi

# ---- T5 ----
log "T5 long-press, lift, release"
dismiss_dialogs
sleep 2
xy=$(xy_of back "$(still_line)")
if [ -n "$xy" ]; then
  set -- $xy; X=$1; Y=$2
  log "grab at $X,$Y"
  TOP=$((SH * 35 / 100))   # 拖到螢幕約 35% 高的位置
  adb shell input motionevent DOWN $X $Y; sleep 1.2
  for k in 1 2 3 4 5 6 7 8 9 10; do adb shell input motionevent MOVE $X $((Y - (Y - TOP) * k / 10)); done
  sleep 1.5; shot 6_held
  adb shell input motionevent UP $X $TOP
  if ! plog | grep -q 'grab at'; then
    log "motionevent did not grab; trying draganddrop"
    adb shell input draganddrop $X $Y $X $TOP 2500 &
    sleep 2.6; shot 6_held
    wait
  fi
  sleep 3; shot 7_landed
  plog > "$OUT/logcat_t5.txt"
  pet_seen 6_held; pet_seen 7_landed
  hy=$(centroid_y 6_held); ly=$(centroid_y 7_landed)
  log "centroid y held=$hy landed=$ly"
  if grep -q 'grab at' "$OUT/logcat_t5.txt" && grep -q 'release v=' "$OUT/logcat_t5.txt" && grep -q 'landed impact=' "$OUT/logcat_t5.txt"; then
    if [ "$hy" -gt 0 ] && [ "$ly" -gt 0 ] && [ $((ly - hy)) -gt $((SH / 6)) ]; then result "PASS T5 picked up (y=$hy), dropped and landed (y=$ly)"; else result "FAIL T5 logs ok but screenshots do not show lift (held=$hy landed=$ly)"; fi
  else
    result "FAIL T5 grab/release/land not in log"
  fi
  if wait_log 'window -> small' 8; then log "window back to small"; fi
else
  result "FAIL T5 no position log"
fi

# ---- T6 ----
log "T6 another app (dialer)"
adb shell am start -a android.intent.action.DIAL > /dev/null 2>&1; sleep 5; dismiss_dialogs; sleep 1; shot 8_over_dialer
if pet_up t6 && pet_seen 8_over_dialer; then result "PASS T6 cat floats over another app"; else result "FAIL T6 cat not over other app"; fi

# ---- T7 ----
log "T7 microphone switch (info)"
launch; sleep 5
adb shell input swipe $((SW / 2)) $((SH * 8 / 10)) $((SW / 2)) $((SH * 2 / 10)) 400; sleep 1   # 開關在頁面下方，先往下捲
if tap_label "麥克風：聽得到你" t7; then
  sleep 8
  plog | grep -E 'mic |foreground|overlay (shown|hidden)' | tail -5 >> "$OUT/emulator_steps.txt"
  if plog | grep -q 'mic on'; then result "INFO T7 mic on inside overlay"; else result "INFO T7 mic did not start (see logcat)"; fi
else
  result "INFO T7 mic switch not found"
fi
adb shell dumpsys vibrator_manager 2>/dev/null | grep -i -A2 "$PKG" | head -20 > "$OUT/vibrator.txt" || true

# ---- T9（3D）----
log "T9 switch to 3D"
plog | grep -E '\] perf look=2d' > "$OUT/perf_2d.txt"
launch; sleep 4
for k in 1 2; do adb shell input swipe $((SW / 2)) $((SH * 2 / 10)) $((SW / 2)) $((SH * 8 / 10)) 300; done; sleep 1   # 捲回最上面
if tap_label "3D 實驗" t9; then
  if wait_log '3d ready\|3d unavailable' 40; then
    r=$(plog | grep -oE '3d (ready|unavailable).*' | tail -1 | cut -c1-300)
    case "$r" in "3d ready"*) result "PASS T9 3D renderer loaded ($r)";; *) result "FAIL T9 $r";; esac
  else
    result "FAIL T9 3D never reported"
  fi
  sleep 2; shot 9_control_3d
  adb shell input keyevent KEYCODE_HOME; sleep 5; shot 10_home_3d_a; sleep 4; shot 11_home_3d_b
  diff=$(python3 ci/frame_diff.py "$OUT/10_home_3d_a.png" "$OUT/11_home_3d_b.png" 2>/dev/null)
  log "frame diff 3d a/b = $diff px"
  if pet_seen 10_home_3d_a; then
    if [ "${diff:-0}" -ge 15 ]; then result "PASS T9 3D cat visible over launcher and animating ($(cat $OUT/pixels_10_home_3d_a.txt))"; else result "FAIL T9 3D visible but frozen (diff=$diff)"; fi
  else
    result "FAIL T9 3D cat not visible ($(cat $OUT/pixels_10_home_3d_a.txt 2>/dev/null))"
  fi
  stroke_test T9s 12_stroke_3d
  sleep 6
  plog | grep -E '\] perf look=3d' > "$OUT/perf_3d.txt"
  result "INFO T9 2D perf: $(tail -1 "$OUT/perf_2d.txt" | sed 's/.*perf //')"
  result "INFO T9 3D perf: $(tail -1 "$OUT/perf_3d.txt" | sed 's/.*perf //')"
else
  result "FAIL T9 look switch not found"
fi

# ---- T8 ----
log "T8 hide"
launch; sleep 4
for k in 1 2; do adb shell input swipe $((SW / 2)) $((SH * 2 / 10)) $((SW / 2)) $((SH * 8 / 10)) 300; done; sleep 1   # 捲回最上面
if tap_label "收起來" t8; then
  sleep 4
  if pet_up t8; then result "FAIL T8 overlay still up after hide"; else result "PASS T8 hide works"; fi
else
  result "FAIL T8 hide button not found"
fi

kill "$LOGCAT_PID" 2>/dev/null || true
cp "$OUT/logcat_live.txt" "$OUT/logcat.txt"
plog > "$OUT/pet_log.txt"
exit $FAILED
