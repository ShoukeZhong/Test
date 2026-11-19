import 'dart:math' as math;

import 'species.dart';
import 'util.dart';

enum LifeStage { neonatal, transitional, socialisation, juvenile, adolescent, adult, senior, geriatric, dead }

const Map<LifeStage, String> lifeStageLabel = {
  LifeStage.neonatal: '新生期',
  LifeStage.transitional: '過渡期',
  LifeStage.socialisation: '社會化期',
  LifeStage.juvenile: '幼年',
  LifeStage.adolescent: '青春期',
  LifeStage.adult: '成年',
  LifeStage.senior: '熟齡',
  LifeStage.geriatric: '高齡',
  LifeStage.dead: '已離世',
};

/// 由年齡推出的一切「生理狀態」。全部是連續函數，沒有跳變。
class LifeInfo {
  const LifeInfo(this.sp, this.ageSec, this.lifespanSec, this.dead);

  final SpeciesInfo sp;
  final double ageSec;
  final double lifespanSec;
  final bool dead;

  double get days => ageSec / kDay;
  double get years => ageSec / kYear;

  LifeStage get stage {
    if (dead) return LifeStage.dead;
    final d = days;
    if (d < 14) return LifeStage.neonatal;
    if (d < 28) return LifeStage.transitional;
    if (d < sp.weanEndDay) return LifeStage.socialisation;
    if (d < 182) return LifeStage.juvenile;
    if (d < sp.adultDay) return LifeStage.adolescent;
    if (years < sp.seniorYears) return LifeStage.adult;
    if (years < sp.seniorYears + 5) return LifeStage.senior;
    return LifeStage.geriatric;
  }

  /// 體型 0.25（出生）→ 1.0（成年）
  double get growth => 1 - 0.75 * math.exp(-days / (sp.adultDay / 4.5));

  /// 幼體頭比較大、腿比較短
  double get headRatio => 1 + 0.55 * math.exp(-days / 60);
  double get legRatio => 1 - 0.4 * math.exp(-days / 45);

  /// 眼睛：開眼日前後約 3 天內慢慢睜開
  double get eyesCanOpen => clampD((days - (sp.eyesOpenDay - 1.5)) / 3, 0, 1);
  bool get canHear => days >= sp.hearingDay;
  bool get canSee => eyesCanOpen > 0.6;

  /// 行動力：新生只能爬，學會走路後到 1；老年慢慢下降
  double get mobility {
    final young = clampD((days - 2) / (sp.walkDay - 2), 0.08, 1);
    final old = years > sp.seniorYears ? clampD(1 - 0.05 * (years - sp.seniorYears), 0.45, 1) : 1.0;
    return young * old * (1 - 0.6 * endOfLife);
  }

  /// 學走路後兩週內搖搖晃晃
  double get wobble => days < sp.walkDay ? 1.0 : clampD(1 - (days - sp.walkDay) / 14, 0, 1);

  bool get motherCares => days < sp.weanStartDay;
  double get weaning => clampD((days - sp.weanStartDay) / (sp.weanEndDay - sp.weanStartDay), 0, 1);
  bool get motherPresent => days < sp.weanEndDay;
  bool get usesToilet => days >= sp.weanStartDay;

  /// 一天睡多少比例
  double get sleepTarget {
    final d = days, y = years;
    if (d < 14) return 0.9; // 〔查證〕新生幼貓約 90% 時間在睡
    if (d < 56) return lerpD(0.9, 0.75, (d - 14) / 42);
    if (d < 365) return lerpD(0.75, 0.62, (d - 56) / 309);
    if (y < sp.seniorYears) return 0.58; // 〔查證〕成貓 12–16 小時
    if (y < sp.seniorYears + 5) return lerpD(0.58, 0.72, (y - sp.seniorYears) / 5); // 〔查證〕老貓 16–20 小時
    return 0.78;
  }

  double get youth => math.exp(-days / 150);

  /// 最後 45 天從 0 升到 1：體力、健康上限一起下降
  double get endOfLife => lifespanSec <= 0 ? 0 : clampD(1 - (lifespanSec - ageSec) / (45 * kDay), 0, 1);

  /// 毛色變灰程度
  double get greying => years <= sp.seniorYears - 2 ? 0 : clampD((years - sp.seniorYears + 2) / 8, 0, 0.7);
}
