# 參數與設計依據

標示：〔查證〕＝有找到出處｜〔記憶〕＝未查證，之後要補｜〔估〕＝工程估計，需要用實際體驗調整

## 生理參數（lib/sim/species.dart、life.dart、physiology.dart）

| 參數 | 值 | 出處 |
|---|---|---|
| 貓壽命 | 12–18 年（出生時隨機決定） | 〔查證〕Embrace Pet Insurance、Angel City Vet、Cloud9 Vets：平均 12–18 年，中位數約 14 年 |
| 開眼 | 7–10 天 | 〔查證〕International Cat Care；Pet Circle（Dr Gillian Hill BVSc） |
| 開始聽得到 | 約第 5 天 | 〔查證〕The Happy Cat Site |
| 搖晃走路 | 第 2–3 週 | 〔查證〕International Cat Care；Royal Canin |
| 斷奶 | 約 4 週開始、8 週完成 | 〔查證〕Royal Canin；Pet Circle |
| 新生兒排泄靠母貓刺激 | — | 〔查證〕Pet Circle |
| 新生兒睡眠 | 約 90% | 〔查證〕Royal Canin；WebVet：新生幼貓每天睡 20–22 小時 |
| 成貓睡眠 | 12–16 小時 | 〔查證〕WebVet；Inverse 訪問的獸醫行為專家 |
| 老貓睡眠 | 16–20 小時 | 〔查證〕WebVet |
| 成貓尺寸 | 約 12 個月 | 〔查證〕Royal Canin |
| 排尿 | 成貓每天 2–4 次 | 〔查證〕Cats Protection；Rover；Hepper（獸醫審閱） |
| 排便 | 成貓每天 1–2 次，幼貓更頻繁 | 〔查證〕Cats Protection；Litter-Robot |
| 貓砂盆太髒會排在外面 | — | 〔查證〕Hepper |
| 幼貓眼睛先是藍灰色 | — | 〔查證〕Cats Protection（Countryfile 訪問） |
| 狗的各項參數 | 見 species.dart | 〔記憶〕下一輪要查證 |
| 呼吸頻率、食量、水量、健康下降速度 | 見 physiology.dart | 〔估〕 |

## 行為與個性

- Litchfield, C. A. et al. (2017). The ‘Feline Five’. PLOS ONE 12(8): e0183455. https://doi.org/10.1371/journal.pone.0183455
- Jones, A. C. & Gosling, S. D. (2005). Temperament and personality in dogs. Applied Animal Behaviour Science 95: 1–53. https://doi.org/10.1016/j.applanim.2005.04.008
- Stanton, L. A. et al. (2015). A standardized ethogram for the felidae. Applied Animal Behaviour Science 173: 3–16. https://doi.org/10.1016/j.applanim.2015.04.001
- Blumberg, B. M. (1996). Old Tricks, New Dogs: Ethology and Interactive Creatures. MIT PhD thesis. https://characters.media.mit.edu/Theses/blumberg_phd.pdf
- Blumberg, B. M. & Galyean, T. A. (1995). Multi-level direction of autonomous creatures for real-time virtual environments. SIGGRAPH ’95.（行為層 → 運動層 → 幾何層的分層架構）
- Mark, D. (2009). Behavioral Mathematics for Game AI；Mark & Dill (2010) GDC。（效用式決策）

## 連續動畫

- Holden, D. "Spring-It-On: The Game Developer's Spring-Roll-Call"（臨界阻尼彈簧）〔記憶〕
- Clavet, S. (2016). Motion Matching and The Road to Next-Gen Animation. GDC 2016.
- Zhang, H., Starke, S., Komura, T. & Saito, J. (2018). Mode-Adaptive Neural Networks for Quadruped Motion Control. ACM TOG 37(4). https://doi.org/10.1145/3197517.3201366（之後要讓步態更真實可走這條）
- Holden, D. et al. (2020). Learned Motion Matching. SIGGRAPH 2020. https://doi.org/10.1145/3386569.3392440
- Wang, X. et al. (2025). AniMo: Species-Aware Model for Text-Driven Animal Motion Generation. CVPR 2025.（文字生成動物動作）

## 感測

- MediaPipe Tasks（之後若要做臉部／手部偵測）：https://developers.google.com/edge/mediapipe/solutions
- camera 套件：https://pub.dev/packages/camera
- record 套件：https://pub.dev/packages/record
