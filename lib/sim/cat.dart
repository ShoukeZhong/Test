/// 貓的身體參數。出處標示見 docs/SOURCES.md：
/// 〔查證〕有找到資料｜〔記憶〕未在這次查證｜〔估〕工程估計，要用實際體驗調整。
class CatBody {
  CatBody._();

  /// 世界單位：1 單位 ≈ 1.8 cm（成貓頭身長約 46 cm〔記憶〕÷ 骨架 26 單位）〔估〕
  static const double bodyLength = 26;
  static const double legLength = 10;
  static const double walkSpeed = 18;
  static const double runSpeed = 60;

  /// 成貓一天睡 12–16 小時 → 約 58% 時間在睡〔查證〕
  static const double sleepFraction = 0.58;

  /// 1 單位 ≈ 1.8 cm 時，重力 9.81 m/s² ≈ 545 單位/s²（拎起、掉落用）〔估〕
  static const double gravity = 545;
}
