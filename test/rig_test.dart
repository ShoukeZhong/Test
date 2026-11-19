import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_overlay/anim/rig.dart';
import 'package:pet_overlay/anim/spring.dart';
import 'package:pet_overlay/sim/life.dart';
import 'package:pet_overlay/sim/motor.dart';
import 'package:pet_overlay/sim/species.dart';
import 'package:pet_overlay/sim/util.dart';

List<V2> _points(RigFrame r) => [
      r.head,
      r.hip,
      r.shoulder,
      for (final l in r.legs) ...[l.knee, l.foot],
    ];

/// 回傳 (身體各點最大單幀位移, 尾巴尖最大單幀位移)
(double, double) _maxJump(Species sp, double ageDays) {
  final rig = PetRig(sp, 50);
  final loco = Locomotion()..x = 50;
  final it = MotorIntent();
  final life = LifeInfo(infoOf(sp), ageDays * kDay, 15 * kYear, false);
  final postures = Posture.values;
  final rng = math.Random(3);
  List<V2>? prev;
  V2? prevTip;
  var worst = 0.0, worstTip = 0.0;
  for (var frame = 0; frame < 1800; frame++) {
    if (frame % 40 == 0) {
      // 每 2/3 秒就突然換一個完全不同的目標：姿勢、位置、視線、表情
      it.reset();
      it.posture = postures[rng.nextInt(postures.length)];
      it.targetX = rng.nextBool() ? 15 + rng.nextDouble() * 70 : null;
      it.speed = rng.nextBool() ? 60 : 18;
      it.headDip = rng.nextDouble();
      it.lookAtViewer = rng.nextBool() ? 1 : 0;
      it.tailUp = rng.nextDouble() * 2 - 1;
      it.tailWag = rng.nextDouble();
      it.pawLift = rng.nextBool() ? 1 : 0;
      it.eyes = rng.nextDouble();
      it.dig = rng.nextBool() ? 1 : 0;
    }
    loco.update(1 / 60, it, mobility: 1);
    final r = rig.update(1 / 60, it, loco.x, loco.vx, life);
    final pts = _points(r);
    for (final p in pts) {
      expect(p.x.isFinite && p.y.isFinite, isTrue);
    }
    if (prev != null && prevTip != null && frame > 2) {
      for (var i = 0; i < pts.length; i++) {
        worst = math.max(worst, pts[i].dist(prev[i]));
      }
      worstTip = math.max(worstTip, r.tail.last.dist(prevTip));
    }
    prev = pts;
    prevTip = r.tail.last;
  }
  return (worst, worstTip);
}

void main() {
  test('彈簧：目標突變時位置連續、最後收斂', () {
    final s = Spring(0);
    var last = 0.0;
    var maxStep = 0.0;
    for (var i = 0; i < 120; i++) {
      s.update(10, 0.1, 1 / 60);
      maxStep = math.max(maxStep, (s.x - last).abs());
      last = s.x;
    }
    expect(s.x, closeTo(10, 0.01));
    expect(maxStep, lessThan(3)); // 沒有一幀直接跳到 10
  });

  // 成貓體長 26 單位；跑步時身體每幀約移動 1 單位。
  // 如果是「一個動作切到另一個動作」，同一點一幀內會跳 10–25 單位。
  test('成貓骨架：亂切姿勢與目標，每幀位移都很小（畫面連續）', () {
    final (worst, tip) = _maxJump(Species.cat, 900);
    // ignore: avoid_print
    print('cat worst body=$worst tailTip=$tip');
    expect(worst, lessThan(3.5));
    expect(tip, lessThan(6.0));
  });

  test('幼犬骨架也一樣連續', () {
    final (worst, tip) = _maxJump(Species.dog, 40);
    // ignore: avoid_print
    print('puppy worst body=$worst tailTip=$tip');
    expect(worst, lessThan(3.5));
    expect(tip, lessThan(6.0));
  });
}
