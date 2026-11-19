import 'package:flutter_test/flutter_test.dart';
import 'package:pet_overlay/sim/brain.dart';
import 'package:pet_overlay/sim/needs.dart';
import 'package:pet_overlay/sim/profile.dart';
import 'package:pet_overlay/sim/simulator.dart';
import 'package:pet_overlay/sim/stimuli.dart';

Simulator _cat(String desc, {int seed = 1}) {
  final sim = Simulator(traits: compileTraits(desc).$1, seed: seed);
  sim.loco
    ..minX = 20
    ..maxX = 180
    ..x = 100;
  sim.needs.fatigue = 0.1;
  return sim;
}

Set<Act> _run(Simulator sim, double seconds, {void Function(double t)? each}) {
  final seen = <Act>{};
  var t = 0.0;
  while (t < seconds) {
    each?.call(t);
    sim.step(1 / 60);
    seen.add(sim.brain.act);
    t += 1 / 60;
    if (!sim.carried) {
      expect(sim.loco.x, inInclusiveRange(sim.loco.minX - 0.5, sim.loco.maxX + 0.5));
    }
  }
  return seen;
}

void main() {
  group('個性描述', () {
    test('典型描述', () {
      final (t, m) = compileTraits('很懶、有點怕生，但很黏主人');
      final b = Traits.base();
      expect(t.activity, lessThan(b.activity));
      expect(t.fearfulness, greaterThan(b.fearfulness));
      expect(t.fearfulness - b.fearfulness, lessThan(0.3)); // 「有點」只加一點
      expect(t.sociability, greaterThan(b.sociability));
      expect(m, ['懶', '怕生', '黏']);
    });
    test('否定詞不重複計算', () {
      final (t, m) = compileTraits('不黏人');
      expect(t.sociability, closeTo(Traits.base().sociability - 0.3, 1e-9));
      expect(m, ['不黏人']);
    });
  });

  test('睡眠比例：長時間下來接近成貓的 12–16 小時', () {
    final n = Needs()..fatigue = 0.5;
    final t = Traits.base();
    var asleep = false, slept = 0.0, total = 0.0;
    const dt = 10.0;
    for (var i = 0; i < 3 * 24 * 360; i++) {
      if (!asleep && n.fatigue >= 0.8) asleep = true;
      if (asleep && n.fatigue <= 0.06) asleep = false;
      n.tick(dt, t, asleep: asleep);
      if (asleep) slept += dt;
      total += dt;
    }
    expect(slept / total, inInclusiveRange(0.5, 0.67));
  });

  group('即時行為', () {
    test('親人的貓被摸頭會呼嚕', () {
      final sim = _cat('超級黏人', seed: 6);
      var purred = false;
      _run(sim, 6, each: (t) {
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
      final sim = _cat('高冷、獨立', seed: 7);
      var swat = false;
      _run(sim, 40, each: (t) {
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
      final sim = _cat('很膽小', seed: 8);
      _run(sim, 2);
      sim.stim
        ..loudOnset = true
        ..soundLevel = 0.9;
      final seen = _run(sim, 1);
      expect(seen, contains(Act.startle));
    });

    test('在旁邊滑手指，牠會進入追手指', () {
      final sim = _cat('活潑、好奇', seed: 9);
      sim.needs.boredom = 0.5;
      final seen = _run(sim, 4, each: (t) {
        sim.stim
          ..fingerX = 100 + 20 * (t % 1)
          ..fingerY = 2
          ..fingerSpeed = 15;
      });
      expect(seen, contains(Act.hunt));
    });

    test('被抱起：膽小的會掙扎，黏人的比較放鬆', () {
      double struggleOf(String desc, int seed) {
        final sim = _cat(desc, seed: seed);
        sim.carried = true;
        var sum = 0.0;
        var n = 0;
        _run(sim, 3, each: (t) {
          if (t > 0.5) {
            sum += sim.brain.intent.struggle;
            n++;
          }
        });
        expect(sim.brain.act, Act.held);
        return sum / n;
      }

      final shy = struggleOf('很膽小、不讓抱', 10);
      final cuddly = struggleOf('超級黏人、淡定', 11);
      expect(shy, greaterThan(0.3));
      expect(cuddly, lessThan(0.15));
    });

    test('重重摔下：膽小的貓落地後逃開；輕輕放下就沒事', () {
      Set<Act> afterLanding(String desc, double impact, int seed) {
        final sim = _cat(desc, seed: seed);
        sim.carried = true;
        _run(sim, 1);
        sim.carried = false;
        sim.landImpact = impact;
        return _run(sim, 1.5);
      }

      expect(afterLanding('很膽小', 450, 12), containsAll([Act.land, Act.startle]));
      expect(afterLanding('超級黏人、淡定', 20, 13), isNot(contains(Act.startle)));
    });
  });
}
