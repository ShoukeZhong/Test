import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_overlay/sim/brain.dart';
import 'package:pet_overlay/sim/life.dart';
import 'package:pet_overlay/sim/physiology.dart';
import 'package:pet_overlay/sim/profile.dart';
import 'package:pet_overlay/sim/simulator.dart';
import 'package:pet_overlay/sim/species.dart';
import 'package:pet_overlay/sim/state.dart';
import 'package:pet_overlay/sim/stimuli.dart';
import 'package:pet_overlay/sim/util.dart';
import 'package:pet_overlay/sim/world.dart';

PetState _pet({double ageYears = 0, String desc = '', Species sp = Species.cat, int seed = 1}) {
  final (traits, _) = compileTraits(sp, desc);
  final s = PetState.newborn(species: sp, name: '測試', traits: traits, coat: 0, nowMs: 0, seed: seed);
  s.ageSec = ageYears * kYear;
  if (ageYears > 0) {
    for (final m in ['hearing', 'eyes', 'walk', 'wean', 'independent', 'adult']) {
      s.milestones.add(m);
    }
    s.needs.fatigue = 0.3;
  }
  return s;
}

void main() {
  group('個性描述', () {
    test('典型描述', () {
      final (t, m) = compileTraits(Species.cat, '很懶、超貪吃、有點怕生，但很黏主人');
      final b = Traits.base(Species.cat);
      expect(t.activity, lessThan(b.activity));
      expect(t.appetite, greaterThan(b.appetite));
      expect(t.fearfulness, greaterThan(b.fearfulness));
      expect(t.fearfulness - b.fearfulness, lessThan(0.3));
      expect(t.sociability, greaterThan(b.sociability));
      expect(m, ['懶', '貪吃', '怕生', '黏']);
    });
    test('否定詞不重複計算', () {
      final (t, m) = compileTraits(Species.cat, '不愛吃');
      expect(t.appetite, closeTo(Traits.base(Species.cat).appetite - 0.3, 1e-9));
      expect(m, ['不愛吃']);
    });
  });

  group('生命階段（連續）', () {
    LifeInfo at(double days) => LifeInfo(catInfo, days * kDay, 15 * kYear, false);
    test('出生閉眼、7–10 天開眼', () {
      expect(at(3).eyesCanOpen, 0);
      expect(at(3).stage, LifeStage.neonatal);
      expect(at(12).eyesCanOpen, greaterThan(0.9));
      expect(at(30).stage, LifeStage.socialisation);
      expect(at(400).stage, LifeStage.adult);
      expect(at(11 * 365.25).stage, LifeStage.senior);
    });
    test('體型單調長大，沒有跳變', () {
      var prev = at(0).growth;
      expect(prev, closeTo(0.25, 0.01));
      for (var d = 0.5; d < 800; d += 0.5) {
        final g = at(d).growth;
        expect(g, greaterThanOrEqualTo(prev));
        expect(g - prev, lessThan(0.01));
        prev = g;
      }
      expect(at(365).growth, greaterThan(0.98));
    });
  });

  group('離線補算（吃喝拉撒睡）', () {
    test('新生 10 天由媽媽照顧：活著、不餓、開眼', () {
      final s = _pet();
      final w = World()
        ..food = 0
        ..water = 0;
      final r = CatchUp.run(s, w, 10 * kDay, 0, math.Random(1));
      expect(r.died, isFalse);
      expect(s.needs.hunger, lessThan(0.5));
      expect(s.health, greaterThan(0.9));
      expect(s.milestones, containsAll(['hearing', 'eyes']));
    });

    test('成貓 3 天：排泄次數、睡眠比例在獸醫資料範圍內', () {
      final s = _pet(ageYears: 3);
      final w = World();
      for (var d = 0; d < 3; d++) {
        w
          ..food = 1
          ..water = 1;
        w.toilet.clear();
        CatchUp.run(s, w, kDay, 0, math.Random(d));
      }
      expect(s.dead, isFalse);
      expect(s.urinations, inInclusiveRange(6, 14)); // 每天 2–4 次
      expect(s.defecations, inInclusiveRange(2, 8)); // 每天 1–2 次
      final sleep = s.sleptSec / (s.sleptSec + s.awakeSec);
      expect(sleep, inInclusiveRange(0.45, 0.72)); // 12–16 小時 ≈ 0.5–0.67
      expect(s.accidents, 0);
    });

    test('沒水沒飯 10 天會死亡', () {
      final s = _pet(ageYears: 3);
      final w = World()
        ..food = 0
        ..water = 0;
      final r = CatchUp.run(s, w, 10 * kDay, 0, math.Random(2));
      expect(r.died, isTrue);
      expect(s.deathCause, '脫水');
    });

    test('壽命到了會自然離世', () {
      final s = _pet(ageYears: 0);
      s.ageSec = s.lifespanSec - 2 * kDay;
      for (final m in ['hearing', 'eyes', 'walk', 'wean', 'independent', 'adult', 'senior', 'geriatric']) {
        s.milestones.add(m);
      }
      final w = World();
      for (var d = 0; d < 5 && !s.dead; d++) {
        w
          ..food = 1
          ..water = 1;
        w.toilet.clear();
        CatchUp.run(s, w, kDay, 0, math.Random(3 + d));
      }
      expect(s.dead, isTrue);
      expect(s.deathCause, '壽終正寢');
    });

    test('貓砂盆太髒會尿在地上', () {
      final s = _pet(ageYears: 3);
      final w = World();
      for (var i = 0; i < World.toiletRefuseCount; i++) {
        w.toilet.add(Waste(WasteKind.feces, World.toiletX));
      }
      CatchUp.run(s, w, kDay, 0, math.Random(4));
      expect(s.accidents, greaterThan(0));
      expect(w.floor, isNotEmpty);
    });

    test('存檔再讀回來一致', () {
      final s = _pet(ageYears: 2);
      s.needs.hunger = 0.42;
      final back = PetState.fromJson(s.toJson());
      expect(back.ageSec, s.ageSec);
      expect(back.needs.hunger, 0.42);
      expect(back.lifespanSec, s.lifespanSec);
      expect(back.events.length, s.events.length);
    });
  });

  group('即時行為', () {
    Set<Act> run(Simulator sim, double seconds, {void Function(double t)? each}) {
      final seen = <Act>{};
      var t = 0.0;
      while (t < seconds) {
        each?.call(t);
        sim.step(1 / 60, (t * 1000).round());
        seen.add(sim.brain.act);
        t += 1 / 60;
        expect(sim.loco.x, inInclusiveRange(World.minX, World.maxX));
      }
      return seen;
    }

    test('沒飯會討飯，倒了飼料就去吃', () {
      final s = _pet(ageYears: 2);
      final w = World()..food = 0;
      s.needs.hunger = 0.9;
      s.needs.fatigue = 0.1;
      final sim = Simulator(s, w, seed: 5);
      final seen = run(sim, 90);
      expect(seen, contains(Act.askFood));
      w.food = 1;
      final seen2 = run(sim, 30);
      expect(seen2, contains(Act.eat));
      expect(s.needs.hunger, lessThan(0.9));
    });

    test('親人的貓被摸頭會呼嚕', () {
      final s = _pet(ageYears: 2, desc: '超級黏人');
      s.needs.fatigue = 0.1;
      final sim = Simulator(s, World(), seed: 6);
      var purred = false;
      run(sim, 6, each: (t) {
        sim.stim
          ..strokeRegion = BodyRegion.head
          ..strokeSpeed = 25
          ..sinceStroke = 0
          ..touchingPet = true;
        if (sim.brain.intent.purr) purred = true;
      });
      expect(purred, isTrue);
    });

    test('一直摸高冷貓的肚子會被揮爪然後走開', () {
      final s = _pet(ageYears: 2, desc: '高冷、獨立');
      s.needs.fatigue = 0.1;
      final sim = Simulator(s, World(), seed: 7);
      var swat = false;
      run(sim, 40, each: (t) {
        if (sim.brain.act == Act.petted && sim.brain.phase == 9) swat = true;
        if (!swat) {
          sim.stim
            ..strokeRegion = BodyRegion.belly
            ..strokeSpeed = 25
            ..sinceStroke = 0;
        }
      });
      expect(swat, isTrue);
    });

    test('膽小的貓聽到巨響會受驚', () {
      final s = _pet(ageYears: 2, desc: '很膽小');
      s.needs.fatigue = 0.1;
      final sim = Simulator(s, World(), seed: 8);
      run(sim, 2);
      sim.stim
        ..loudOnset = true
        ..soundLevel = 0.9;
      final seen = run(sim, 1);
      expect(seen, contains(Act.startle));
    });
  });
}
