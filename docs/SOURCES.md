# 參數與設計依據

標示：〔查證〕＝有找到出處｜〔記憶〕＝未查證，之後要補｜〔估〕＝工程估計，需要用實際體驗調整

第一版（懸浮貓）**不做**：壽命、成長、老化、死亡、飢餓、口渴、排泄、照顧責任、狗、球、房間場景。

## 身體與內在狀態（lib/sim/cat.dart、needs.dart）

| 參數 | 值 | 出處 |
|---|---|---|
| 成貓睡眠 | 12–16 小時 → 睡眠比例 0.58 | 〔查證〕WebVet；Inverse 訪問的獸醫行為專家 |
| 頭身長 | 約 46 cm → 1 單位 ≈ 1.8 cm | 〔記憶〕 |
| 重力 | 545 單位/s²（9.81 m/s² ÷ 1.8 cm） | 由上一列換算〔估〕 |
| 疲倦恢復、無聊、寂寞累積速度、恐懼消退 | 見 needs.dart | 〔估〕 |

## 抱起、掉落（lib/overlay/pet_body.dart）

- 抱著：物理擺（physical pendulum），支點在胸口；手指加速度用「等效重力 g − a」加進去，所以甩手會讓身體晃。阻尼比 0.45、迴轉半徑 0.3 體長、感受加速度上限 1.5 g〔估〕。
- 放手：拋體運動；翻正反射用臨界阻尼彈簧把身體轉回腳朝下（半衰期 0.1 s）〔估〕。真實機制（身體前後兩段反向扭轉、總角動量為零）：
  - Kane, T. R. & Scher, M. P. (1969). A dynamical explanation of the falling cat phenomenon. International Journal of Solids and Structures 5(7): 663–670. https://doi.org/10.1016/0020-7683(69)90086-9 〔查證〕
- 落地：找身體最低點碰地的那一刻（每幀 4 個子步），切回地面；剩下的傾斜和高度用彈簧收掉，身體座標平移對齊（rebase），畫面不跳。
- 落地後理毛（被搬動後的自我安撫）〔記憶〕；撞擊越重越怕〔估〕。

## 觸覺

- 呼嚕震動 25 Hz（20 ms 震、20 ms 停）：
  - 家貓呼嚕基頻約 20–30 Hz〔查證〕：Herbst, C. T. et al. (2023). Domestic cat larynges can produce purring frequencies without neural input. Current Biology 33: 4727–4732；Remmers, J. E. & Gautier, H. (1972). Neural and mechanical mechanisms of feline purring. Respiration Physiology 16: 351–361。
- 長按 450 ms 抱起、移動超過 8 dp 才算撫摸（接近 Android 預設的長按時間與 touch slop）〔記憶〕。

## Android 懸浮視窗與前景服務

- Android 14 起，建立 microphone 類型的前景服務時系統會檢查 RECORD_AUDIO，沒有就丟 SecurityException；在背景建立 camera／microphone 類型的前景服務也會被擋〔查證〕：Android Developers「Foreground service types are required」「Restrictions on starting a foreground service from the background」。
  → 所以 packages/flutter_overlay_window 改成依「已授權的權限」組合類型，而且只從控制 App（前景）啟動；改開關時重開一次服務。
- flutter_overlay_window 1.0.2 原始碼（MIT，X-SLAYER）：`showOverlay` 的寬高是實體像素、`moveOverlay`／`resizeOverlay` 是 dp；`onTouch` 只在 enableDrag 時攔截〔查證：讀原始碼〕。修改內容見 packages/flutter_overlay_window/PET_LIFE_CHANGES.md。
- 模擬器：reactivecircus/android-emulator-runner 的 `profile` 參數（README 範例 `pixel_7_pro`）〔查證：讀 README〕。

## 行為與個性

- Litchfield, C. A. et al. (2017). The ‘Feline Five’. PLOS ONE 12(8): e0183455. https://doi.org/10.1371/journal.pone.0183455
- Stanton, L. A. et al. (2015). A standardized ethogram for the felidae. Applied Animal Behaviour Science 173: 3–16. https://doi.org/10.1016/j.applanim.2015.04.001
- Blumberg, B. M. (1996). Old Tricks, New Dogs: Ethology and Interactive Creatures. MIT PhD thesis. https://characters.media.mit.edu/Theses/blumberg_phd.pdf
- Blumberg, B. M. & Galyean, T. A. (1995). Multi-level direction of autonomous creatures for real-time virtual environments. SIGGRAPH ’95.（行為層 → 運動層 → 幾何層的分層架構）
- Mark, D. (2009). Behavioral Mathematics for Game AI；Mark & Dill (2010) GDC。（效用式決策）
- 撫摸偏好（臉頰、頭最喜歡，肚子、尾巴不喜歡）與過度刺激後揮爪〔記憶〕

## 連續動畫

- Holden, D. "Spring-It-On: The Game Developer's Spring-Roll-Call"（臨界阻尼彈簧）〔記憶〕
- Clavet, S. (2016). Motion Matching and The Road to Next-Gen Animation. GDC 2016.
- Zhang, H., Starke, S., Komura, T. & Saito, J. (2018). Mode-Adaptive Neural Networks for Quadruped Motion Control. ACM TOG 37(4). https://doi.org/10.1145/3197517.3201366（之後要讓步態更真實可走這條）
- Holden, D. et al. (2020). Learned Motion Matching. SIGGRAPH 2020. https://doi.org/10.1145/3386569.3392440

## 感測

- camera 套件：https://pub.dev/packages/camera
- record 套件：https://pub.dev/packages/record
- MediaPipe Tasks（之後若要做臉部／手部偵測）：https://developers.google.com/edge/mediapipe/solutions

## 3D 可行性實驗（lib/three/）

- flutter_scene 0.24.x（Flutter GPU 上的 3D 引擎）：https://pub.dev/packages/flutter_scene 、原始碼 https://github.com/bdero/flutter_scene
  - 需 Flutter 3.47 stable 以上；Android 在 `<application>` 加 `io.flutter.embedding.android.EnableFlutterGPU` meta-data（套件 README「Enable Flutter GPU」）〔官方文件〕
  - `Scene.skybox` 為 null 時背景清成透明；`ShadowCatcherMaterial` 是只畫影子的隱形地板（`scene.dart`、`material/shadow_catcher_material.dart`）〔原始碼〕
  - 自訂 `CameraProjection` 會被讀回矩陣、自動反轉深度（`render/depth_raster.dart` 的 `rasterProjectionMatrix`）〔原始碼〕
  - 父節點的動畫播放器先算、子節點的元件後算（`node.dart` 的 `scenePrePass`），所以掛在頭骨上的元件能在動畫之後再疊轉動〔原始碼〕
  - `Scene.raycast` 對蒙皮網格只用靜止姿勢（`raycast.dart`），所以觸控改用骨頭投影判斷〔原始碼〕
- 替身模型 Fox：Khronos glTF Sample Assets，授權見 `assets/models/Fox.LICENSE.md`（CC0＋CC BY 4.0，需標示作者）
  - 尺寸與步態速度是用 `Fox.glb` 本身算的（本次對話中執行）：尾巴根到鼻尖約 93 模型單位；Walk 0.708 s、Run 1.158 s；腳掌觸地時往後移的速度約 110（走）、220（跑）模型單位／秒 → 播放速度＝貓的速度 ÷ 這個速度，腳不打滑
- 「螢幕是一扇窗」的投影（off-axis／generalized perspective projection）：Kooima, R. (2008). Generalized Perspective Projection.〔記憶〕。視角 30°：手機在 30 cm 外、螢幕高約 15 cm 時張角約 28°（幾何計算）
- 耗電：`BatteryManager.BATTERY_PROPERTY_CURRENT_NOW`（瞬間電流，µA；正負號依廠商而異）https://developer.android.com/reference/android/os/BatteryManager
- 每幀時間：`SchedulerBinding.addTimingsCallback` 的 `FrameTiming.buildDuration`／`rasterDuration`（release 版也有）https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html
