import 'dart:math' as math;

import 'life.dart';
import 'state.dart';
import 'util.dart';
import 'world.dart';

/// 生理時鐘：年齡、需求、健康、里程碑、死亡。即時模式和離線補算共用同一套公式。
class Physiology {
  /// 一滿碗飼料／水各約一天份（成年）〔估〕
  static const double hungerPerFood = 2.4;
  static const double thirstPerWater = 2.7;

  static LifeInfo lifeOf(PetState s) => LifeInfo(s.info, s.ageSec, s.lifespanSec, s.dead);

  static void tick(PetState s, World w, double dt, {required bool asleep, double load = 0, required int nowMs}) {
    if (s.dead || dt <= 0) return;
    s.ageSec += dt;
    final life = lifeOf(s);
    final t = s.traits;
    final n = s.needs;
    final sp = s.info;

    // --- 需求自然變化 ---
    final hungerH = lerpD(6, 10, clampD(life.growth, 0, 1));
    n.hunger += dt / (hungerH * kHour) * (0.7 + 0.6 * t.appetite);
    n.thirst += dt / (9 * kHour);
    // 碗裡的水會慢慢蒸發〔估〕
    w.water = math.max(0.0, w.water - dt / (6 * kDay));
    final youngBoost = 1 + life.youth;
    n.bladder += dt * 0.8 * sp.urinationsPerDay * youngBoost / kDay;
    n.bowel += dt * 0.8 * sp.defecationsPerDay * youngBoost / kDay;

    // 睡眠：恢復速度固定，清醒時累積速度依年齡設定的睡眠比例反推
    final recover = 1 / (2.5 * kHour) * (0.75 + 0.5 * t.activity); // 懶的睡比較久
    if (asleep) {
      n.fatigue -= dt * recover;
      s.sleptSec += dt;
    } else {
      final f = life.sleepTarget;
      final awakeRate = recover * f / (1 - f) * (0.85 + 0.3 * (1 - t.activity)) * (1 + 2 * load);
      n.fatigue += dt * awakeRate;
      n.boredom += dt / (3 * kHour) * (0.6 + 0.8 * t.activity) * youngBoost;
      s.awakeSec += dt;
    }
    n.loneliness += dt / (5 * kHour) * (0.5 + t.sociability);
    n.fear *= math.exp(-dt / 45);

    // --- 母親照顧（新生到斷奶）---
    if (life.motherPresent) {
      final milk = 1 - life.weaning;
      if (n.hunger > 0.2) n.hunger -= dt * milk / (1.5 * kHour);
      if (n.thirst > 0.2) n.thirst -= dt * milk / (1.5 * kHour);
      if (life.motherCares) {
        // 新生幼貓無法自己排泄，靠母貓舔舐刺激〔查證〕
        n.bladder -= dt / (0.8 * kHour);
        n.bowel -= dt / (0.8 * kHour);
      }
      n.loneliness = math.min(n.loneliness, 0.15);
    }
    n.clampAll();

    // --- 健康 ---
    var dmg = 0.0;
    String? cause;
    if (n.thirst >= 0.98) {
      dmg += 1 / (2.5 * kDay);
      cause = '脫水';
    }
    if (n.hunger >= 0.98) {
      dmg += 1 / (4 * kDay);
      cause ??= '飢餓';
    }
    if (w.floor.length >= 4 || w.toilet.length >= 9) {
      dmg += 1 / (25 * kDay);
      cause ??= '環境髒亂造成的疾病';
    }
    if (dmg > 0) {
      s.health -= dmg * dt;
    } else {
      s.health += dt / (3 * kDay);
    }
    final ceiling = 1 - 0.9 * life.endOfLife;
    s.health = clampD(math.min(s.health, ceiling), 0, 1);

    _milestones(s, life, nowMs);

    if (s.health <= 0) {
      _die(s, nowMs, cause ?? '衰弱');
    } else if (s.ageSec >= s.lifespanSec) {
      _die(s, nowMs, '壽終正寢');
    }
  }

  static void _die(PetState s, int nowMs, String cause) {
    s.dead = true;
    s.deathCause = cause;
    final years = s.ageSec / kYear;
    final ageText = years >= 1 ? '${years.toStringAsFixed(1)} 歲' : '${(s.ageSec / kDay).toStringAsFixed(0)} 天';
    s.addEvent(nowMs, 'died', '${s.name} 離開了（$cause，$ageText）');
  }

  static void _milestones(PetState s, LifeInfo life, int nowMs) {
    final sp = s.info;
    final d = life.days;
    if (d >= sp.hearingDay) s.addEvent(nowMs, 'hearing', '開始聽得到聲音');
    if (d >= sp.eyesOpenDay) s.addEvent(nowMs, 'eyes', '第一次睜開眼睛');
    if (d >= sp.walkDay) s.addEvent(nowMs, 'walk', '搖搖晃晃走出第一步');
    if (d >= sp.weanStartDay) s.addEvent(nowMs, 'wean', '開始學吃固體食物、自己上${sp.toiletLabel}');
    if (d >= sp.weanEndDay) s.addEvent(nowMs, 'independent', '斷奶完成，媽媽離開了');
    if (d >= sp.adultDay) s.addEvent(nowMs, 'adult', '長大成年');
    if (life.years >= sp.seniorYears) s.addEvent(nowMs, 'senior', '進入熟齡');
    if (life.years >= sp.seniorYears + 5) s.addEvent(nowMs, 'geriatric', '進入高齡');
  }

  // --- 行為造成的生理效果（即時模式由行為呼叫；離線補算直接呼叫）---
  static double eat(PetState s, World w, double maxFood) {
    final need = math.max(0.0, s.needs.hunger - 0.05) / hungerPerFood;
    final used = math.min(w.food, math.min(need, maxFood));
    w.food -= used;
    s.needs.hunger -= used * hungerPerFood;
    s.needs.bowel += used * 0.15;
    s.needs.clampAll();
    return used;
  }

  static double drink(PetState s, World w, double maxWater) {
    final need = math.max(0.0, s.needs.thirst - 0.05) / thirstPerWater;
    final used = math.min(w.water, math.min(need, maxWater));
    w.water -= used;
    s.needs.thirst -= used * thirstPerWater;
    s.needs.bladder += used * 0.3;
    s.needs.clampAll();
    return used;
  }

  /// 排泄。回傳 true = 在廁所，false = 意外（地板）
  static bool eliminate(PetState s, World w, WasteKind kind, double x, {required bool inToilet}) {
    if (kind == WasteKind.urine) {
      s.needs.bladder = 0;
      s.urinations++;
    } else {
      s.needs.bowel = 0;
      s.defecations++;
    }
    if (inToilet) {
      w.toilet.add(Waste(kind, x));
    } else {
      w.floor.add(Waste(kind, x));
      s.accidents++;
    }
    return inToilet;
  }
}

class CatchUpReport {
  double bioSec = 0;
  int meals = 0;
  int drinks = 0;
  int eliminations = 0;
  int accidents = 0;
  bool died = false;
  @override
  String toString() =>
      'bio=${(bioSec / kHour).toStringAsFixed(1)}h meals=$meals drinks=$drinks elim=$eliminations accidents=$accidents died=$died';
}

/// 離線補算：App 關著的時候，用簡化規則推算牠自己吃喝拉撒睡。
class CatchUp {
  static CatchUpReport run(PetState s, World w, double bioSec, int nowMs, math.Random rng) {
    final r = CatchUpReport()..bioSec = bioSec;
    if (s.dead || bioSec <= 0) return r;
    final step = bioSec > 20 * kDay ? 300.0 : 60.0;
    var left = bioSec;
    while (left > 0 && !s.dead) {
      final dt = math.min(step, left);
      left -= dt;
      final life = Physiology.lifeOf(s);
      final n = s.needs;
      if (!s.asleep && n.fatigue > 0.75) s.asleep = true;
      if (s.asleep && n.fatigue < 0.08) s.asleep = false;
      if (!s.asleep && !life.motherCares) {
        if (n.hunger > 0.55 && w.food > 0 && life.weaning > 0) {
          if (Physiology.eat(s, w, 0.4) > 0) r.meals++;
        }
        if (n.thirst > 0.5 && w.water > 0) {
          if (Physiology.drink(s, w, 0.4) > 0) r.drinks++;
        }
        if (n.boredom > 0.5) n.boredom -= 0.2; // 自己玩一下
      }
      if (life.usesToilet) {
        for (final kind in [WasteKind.urine, WasteKind.feces]) {
          final level = kind == WasteKind.urine ? n.bladder : n.bowel;
          final urgent = level >= 1 || (!s.asleep && level > 0.8);
          if (!urgent) continue;
          final ok = w.toilet.length < World.toiletRefuseCount;
          final x = ok
              ? World.toiletX + (rng.nextDouble() - 0.5) * 8
              : World.minX + 20 + rng.nextDouble() * (World.maxX - World.minX - 25);
          Physiology.eliminate(s, w, kind, x, inToilet: ok);
          r.eliminations++;
          if (!ok) r.accidents++;
        }
      }
      Physiology.tick(s, w, dt, asleep: s.asleep, load: s.asleep ? 0 : 0.1, nowMs: nowMs);
    }
    r.died = s.dead;
    return r;
  }
}
