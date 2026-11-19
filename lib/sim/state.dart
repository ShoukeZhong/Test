import 'dart:math' as math;

import 'profile.dart';
import 'species.dart';
import 'util.dart';

/// 需求：0 = 滿足，1 = 很急
class Needs {
  double hunger = 0.15;
  double thirst = 0.15;
  double bladder = 0.1;
  double bowel = 0.1;
  double fatigue = 0.5;
  double boredom = 0.2;
  double loneliness = 0.2;
  double fear = 0;

  Map<String, double> toJson() => {
        'hunger': hunger,
        'thirst': thirst,
        'bladder': bladder,
        'bowel': bowel,
        'fatigue': fatigue,
        'boredom': boredom,
        'loneliness': loneliness,
        'fear': fear,
      };

  void loadJson(Map<String, dynamic> m) {
    double g(String k, double d) => (m[k] as num?)?.toDouble() ?? d;
    hunger = g('hunger', hunger);
    thirst = g('thirst', thirst);
    bladder = g('bladder', bladder);
    bowel = g('bowel', bowel);
    fatigue = g('fatigue', fatigue);
    boredom = g('boredom', boredom);
    loneliness = g('loneliness', loneliness);
    fear = g('fear', fear);
  }

  void clampAll() {
    hunger = clampD(hunger, 0, 1);
    thirst = clampD(thirst, 0, 1);
    bladder = clampD(bladder, 0, 1);
    bowel = clampD(bowel, 0, 1);
    fatigue = clampD(fatigue, 0, 1);
    boredom = clampD(boredom, 0, 1);
    loneliness = clampD(loneliness, 0, 1);
    fear = clampD(fear, 0, 1);
  }
}

class LifeEvent {
  LifeEvent(this.epochMs, this.ageSec, this.code, this.text);
  final int epochMs;
  final double ageSec;
  final String code;
  final String text;
  Map<String, dynamic> toJson() => {'t': epochMs, 'a': ageSec, 'c': code, 'x': text};
  factory LifeEvent.fromJson(Map<String, dynamic> m) => LifeEvent(
      (m['t'] as num).toInt(), (m['a'] as num).toDouble(), m['c'] as String, m['x'] as String);
}

class PetState {
  PetState({
    required this.species,
    required this.name,
    required this.traits,
    required this.coat,
    required this.seed,
    required this.bornEpochMs,
    required this.lifespanSec,
  }) : lastUpdateEpochMs = bornEpochMs;

  /// 新生命：壽命在物種範圍內隨機（一出生就決定，但不顯示）
  factory PetState.newborn({
    required Species species,
    required String name,
    required Traits traits,
    required int coat,
    required int nowMs,
    int? seed,
  }) {
    final s = seed ?? (nowMs & 0x7fffffff);
    final rng = math.Random(s);
    final sp = infoOf(species);
    final years = sp.lifespanMinYears + rng.nextDouble() * (sp.lifespanMaxYears - sp.lifespanMinYears);
    final st = PetState(
      species: species,
      name: name,
      traits: traits,
      coat: coat,
      seed: s,
      bornEpochMs: nowMs,
      lifespanSec: years * kYear,
    );
    st.needs.fatigue = 0.8; // 剛出生很睏
    st.addEvent(nowMs, 'born', '$name 出生了');
    return st;
  }

  final Species species;
  final String name;
  final Traits traits;
  final int coat;
  final int seed;
  final int bornEpochMs;
  final double lifespanSec;

  double ageSec = 0;
  double health = 1;
  bool dead = false;
  String? deathCause;
  int lastUpdateEpochMs;
  double timeScale = 1; // 開發用：真實 1 秒 = 寵物幾秒
  bool asleep = false; // 離線模擬用
  final Needs needs = Needs();
  final List<LifeEvent> events = [];
  final Set<String> milestones = {};

  // 統計（測試與回顧用）
  int urinations = 0;
  int defecations = 0;
  int accidents = 0;
  double sleptSec = 0;
  double awakeSec = 0;

  SpeciesInfo get info => infoOf(species);

  void addEvent(int nowMs, String code, String text) {
    if (code != 'note' && milestones.contains(code)) return;
    milestones.add(code);
    events.add(LifeEvent(nowMs, ageSec, code, text));
    if (events.length > 80) events.removeAt(0);
    petLog('event $code: $text');
  }

  Map<String, dynamic> toJson() => {
        'v': 2,
        'species': species.index,
        'name': name,
        'traits': traits.toJson(),
        'coat': coat,
        'seed': seed,
        'born': bornEpochMs,
        'lifespan': lifespanSec,
        'age': ageSec,
        'health': health,
        'dead': dead,
        'cause': deathCause,
        'last': lastUpdateEpochMs,
        'timeScale': timeScale,
        'asleep': asleep,
        'needs': needs.toJson(),
        'events': events.map((e) => e.toJson()).toList(),
        'milestones': milestones.toList(),
        'stats': [urinations, defecations, accidents, sleptSec, awakeSec],
      };

  factory PetState.fromJson(Map<String, dynamic> m) {
    final st = PetState(
      species: Species.values[(m['species'] as num).toInt()],
      name: m['name'] as String,
      traits: Traits.fromJson(Map<String, dynamic>.from(m['traits'] as Map)),
      coat: (m['coat'] as num).toInt(),
      seed: (m['seed'] as num).toInt(),
      bornEpochMs: (m['born'] as num).toInt(),
      lifespanSec: (m['lifespan'] as num).toDouble(),
    );
    st.ageSec = (m['age'] as num).toDouble();
    st.health = (m['health'] as num).toDouble();
    st.dead = m['dead'] as bool;
    st.deathCause = m['cause'] as String?;
    st.lastUpdateEpochMs = (m['last'] as num).toInt();
    st.timeScale = (m['timeScale'] as num?)?.toDouble() ?? 1;
    st.asleep = (m['asleep'] as bool?) ?? false;
    st.needs.loadJson(Map<String, dynamic>.from(m['needs'] as Map));
    st.events.addAll((m['events'] as List).map((e) => LifeEvent.fromJson(Map<String, dynamic>.from(e as Map))));
    st.milestones.addAll((m['milestones'] as List).cast<String>());
    final s = (m['stats'] as List?) ?? const [];
    if (s.length == 5) {
      st.urinations = (s[0] as num).toInt();
      st.defecations = (s[1] as num).toInt();
      st.accidents = (s[2] as num).toInt();
      st.sleptSec = (s[3] as num).toDouble();
      st.awakeSec = (s[4] as num).toDouble();
    }
    return st;
  }
}
