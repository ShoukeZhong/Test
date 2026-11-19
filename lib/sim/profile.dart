import 'species.dart';
import 'util.dart';

/// 個性（0..1，0.5 = 一般）。對應 Feline Five：
/// activity≈Extraversion、sociability≈Agreeableness、fearfulness≈Neuroticism、impulsiveness≈Impulsiveness；
/// appetite 是本 app 自訂。
class Traits {
  Traits({
    required this.activity,
    required this.sociability,
    required this.fearfulness,
    required this.impulsiveness,
    required this.appetite,
  });

  double activity;
  double sociability;
  double fearfulness;
  double impulsiveness;
  double appetite;

  factory Traits.base(Species s) => s == Species.dog
      ? Traits(activity: 0.65, sociability: 0.7, fearfulness: 0.35, impulsiveness: 0.5, appetite: 0.6)
      : Traits(activity: 0.45, sociability: 0.45, fearfulness: 0.45, impulsiveness: 0.5, appetite: 0.5);

  Map<String, double> toJson() => {
        'activity': activity,
        'sociability': sociability,
        'fearfulness': fearfulness,
        'impulsiveness': impulsiveness,
        'appetite': appetite,
      };

  factory Traits.fromJson(Map<String, dynamic> m) => Traits(
        activity: (m['activity'] as num).toDouble(),
        sociability: (m['sociability'] as num).toDouble(),
        fearfulness: (m['fearfulness'] as num).toDouble(),
        impulsiveness: (m['impulsiveness'] as num).toDouble(),
        appetite: (m['appetite'] as num).toDouble(),
      );

  double get(String k) => toJson()[k]!;
  void add(String k, double d) {
    switch (k) {
      case 'activity':
        activity += d;
      case 'sociability':
        sociability += d;
      case 'fearfulness':
        fearfulness += d;
      case 'impulsiveness':
        impulsiveness += d;
      case 'appetite':
        appetite += d;
    }
  }

  void clampAll() {
    activity = _r(clampD(activity, 0.05, 0.95));
    sociability = _r(clampD(sociability, 0.05, 0.95));
    fearfulness = _r(clampD(fearfulness, 0.05, 0.95));
    impulsiveness = _r(clampD(impulsiveness, 0.05, 0.95));
    appetite = _r(clampD(appetite, 0.05, 0.95));
  }

  static double _r(double v) => (v * 100).round() / 100;
}

class _Rule {
  const _Rule(this.kw, this.trait, this.delta);
  final List<String> kw;
  final String trait;
  final double delta;
}

const List<_Rule> _rules = [
  _Rule(['懶', '愛睡', '嗜睡', '慵懶', '很宅', '不愛動', '懒'], 'activity', -0.3),
  _Rule(['活潑', '好動', '精力', '過動', '愛跑', '愛玩', '頑皮', '活泼'], 'activity', 0.3),
  _Rule(['黏人', '黏', '親人', '撒嬌', '討摸', '跟屁蟲', '熱情', '粘', '亲人'], 'sociability', 0.3),
  _Rule(['高冷', '獨立', '不理人', '冷淡', '傲嬌', '不讓抱', '独立'], 'sociability', -0.3),
  _Rule(['怕生', '膽小', '容易嚇', '神經質', '緊張', '敏感', '怕人', '胆小'], 'fearfulness', 0.3),
  _Rule(['勇敢', '大膽', '膽大', '淡定', '穩定', '天不怕'], 'fearfulness', -0.3),
  _Rule(['好奇', '調皮', '搗蛋', '衝動', '暴衝', '手賤', '拆家', '调皮'], 'impulsiveness', 0.3),
  _Rule(['穩重', '乖', '安靜', '溫和', '聽話', '佛系'], 'impulsiveness', -0.25),
  _Rule(['貪吃', '愛吃', '嘴饞', '吃貨', '胖', '贪吃'], 'appetite', 0.3),
  _Rule(['挑食', '食量小', '不愛吃', '吃很少'], 'appetite', -0.3),
];

class _Hit {
  _Hit(this.kw, this.start, this.rule);
  final String kw;
  final int start;
  final _Rule rule;
  int get end => start + kw.length;
}

/// 描述文字 → 個性（本地關鍵字規則，成本 0）。回傳 (traits, 認出的詞)。
(Traits, List<String>) compileTraits(Species species, String text) {
  final t = Traits.base(species);
  final hits = <_Hit>[];
  for (final r in _rules) {
    for (final kw in r.kw) {
      var from = 0;
      while (true) {
        final i = text.indexOf(kw, from);
        if (i < 0) break;
        hits.add(_Hit(kw, i, r));
        from = i + kw.length;
      }
    }
  }
  hits.sort((a, b) {
    final c = b.kw.length.compareTo(a.kw.length);
    return c != 0 ? c : a.start.compareTo(b.start);
  });
  final used = <_Hit>[];
  final matched = <(int, String)>[];
  for (final h in hits) {
    if (used.any((u) => h.start < u.end && u.start < h.end)) continue;
    used.add(h);
    final before = text.substring(h.start < 3 ? 0 : h.start - 3, h.start);
    final last2 = before.length <= 2 ? before : before.substring(before.length - 2);
    final neg = !h.kw.startsWith('不') && (last2.contains('不') || last2.contains('沒') || last2.contains('没'));
    var mult = 1.0;
    if (['超', '很', '非常', '特別', '極'].any(last2.contains)) mult = 1.3;
    if (['有點', '有一點', '稍微', '一點'].any(before.contains)) mult = 0.6;
    t.add(h.rule.trait, (neg ? -1 : 1) * mult * h.rule.delta);
    matched.add((h.start, (neg ? '不' : '') + h.kw));
  }
  t.clampAll();
  matched.sort((a, b) => a.$1.compareTo(b.$1));
  return (t, matched.map((m) => m.$2).toList());
}
