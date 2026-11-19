/// 物種參數。出處見 docs/SOURCES.md：
/// 〔查證〕= 有找到獸醫／研究資料；〔記憶〕= 未在這次查證，之後要再確認；〔估〕= 工程上的估計值。
enum Species { cat, dog }

class SpeciesInfo {
  const SpeciesInfo({
    required this.id,
    required this.label,
    required this.lifespanMinYears,
    required this.lifespanMaxYears,
    required this.hearingDay,
    required this.eyesOpenDay,
    required this.walkDay,
    required this.weanStartDay,
    required this.weanEndDay,
    required this.adultDay,
    required this.seniorYears,
    required this.urinationsPerDay,
    required this.defecationsPerDay,
    required this.bodyLength,
    required this.legLength,
    required this.walkSpeed,
    required this.runSpeed,
    required this.toiletLabel,
    required this.voice,
  });

  final Species id;
  final String label;
  final double lifespanMinYears;
  final double lifespanMaxYears;
  final double hearingDay;
  final double eyesOpenDay;
  final double walkDay;
  final double weanStartDay;
  final double weanEndDay;
  final double adultDay;
  final double seniorYears;
  final double urinationsPerDay;
  final double defecationsPerDay;

  /// 成年體長、腿長、速度（世界單位；畫面寬 = 100）〔估〕
  final double bodyLength;
  final double legLength;
  final double walkSpeed;
  final double runSpeed;
  final String toiletLabel;
  final String voice;
}

const SpeciesInfo catInfo = SpeciesInfo(
  id: Species.cat,
  label: '貓',
  lifespanMinYears: 12, // 〔查證〕平均 12–18 年
  lifespanMaxYears: 18,
  hearingDay: 5, // 〔查證〕約第 5 天開始對聲音有反應
  eyesOpenDay: 8.5, // 〔查證〕7–10 天開眼
  walkDay: 16, // 〔查證〕第 2–3 週開始搖晃走路
  weanStartDay: 28, // 〔查證〕約 4 週開始斷奶
  weanEndDay: 56, // 〔查證〕約 8 週完成
  adultDay: 365, // 〔查證〕約 12 個月長到成貓大小
  seniorYears: 10, // 〔查證〕10 歲以上睡得更多
  urinationsPerDay: 3, // 〔查證〕成貓每天 2–4 次
  defecationsPerDay: 1.5, // 〔查證〕成貓每天 1–2 次
  bodyLength: 26,
  legLength: 10,
  walkSpeed: 18,
  runSpeed: 60,
  toiletLabel: '貓砂盆',
  voice: '喵',
);

const SpeciesInfo dogInfo = SpeciesInfo(
  id: Species.dog,
  label: '狗',
  lifespanMinYears: 10, // 〔記憶〕中小型犬約 10–14 年
  lifespanMaxYears: 14,
  hearingDay: 14, // 〔記憶〕
  eyesOpenDay: 12, // 〔記憶〕10–14 天
  walkDay: 18, // 〔記憶〕
  weanStartDay: 28, // 〔記憶〕
  weanEndDay: 56, // 〔記憶〕
  adultDay: 450, // 〔記憶〕12–18 個月
  seniorYears: 8, // 〔記憶〕
  urinationsPerDay: 4, // 〔記憶〕
  defecationsPerDay: 1.5, // 〔記憶〕
  bodyLength: 30,
  legLength: 13,
  walkSpeed: 20,
  runSpeed: 70,
  toiletLabel: '尿布墊',
  voice: '汪',
);

SpeciesInfo infoOf(Species s) => s == Species.dog ? dogInfo : catInfo;
