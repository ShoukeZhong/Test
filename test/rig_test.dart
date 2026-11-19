import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_overlay/anim/rig.dart';
import 'package:pet_overlay/anim/spring.dart';
import 'package:pet_overlay/sim/motor.dart';
import 'package:pet_overlay/sim/util.dart';

List<V2> _points(RigFrame r) => [
      r.head,
      r.hip,
      r.shoulder,
      for (final l in r.legs) ...[l.knee, l.foot],
    ];

const _names = ['head', 'hip', 'shoulder', 'kneeFN', 'footFN', 'kneeFF', 'footFF', 'kneeHN', 'footHN', 'kneeHF', 'footHF'];

/// 回傳 (身體各點最大單幀位移, 尾巴尖最大單幀位移)。[poses] 為 true 時也亂切抱起／懸空。
(double, double) _maxJump({required bool poses, int seed = 3}) {
  final rig = PetRig(50);
  final loco = Locomotion()
    ..x = 50
    ..minX = 10
    ..maxX = 90;
  final it = MotorIntent();
  final rng = math.Random(seed);
  var pose = RigPose.ground;
  var angle = 0.0, omega = 0.0;
  List<V2>? prev;
  V2? prevTip;
  var worst = 0.0, worstTip = 0.0;
  var worstWhere = '';
  for (var frame = 0; frame < 2400; frame++) {
    if (frame % 40 == 0) {
      // 每 2/3 秒就突然換一個完全不同的目標：姿勢、位置、視線、表情
      it.reset();
      it.posture = Posture.values[rng.nextInt(Posture.values.length)];
      it.targetX = rng.nextBool() ? 15 + rng.nextDouble() * 70 : null;
      it.speed = rng.nextBool() ? 60 : 18;
      it.headDip = rng.nextDouble();
      it.lookAtViewer = rng.nextBool() ? 1 : 0;
      it.tailUp = rng.nextDouble() * 2 - 1;
      it.tailWag = rng.nextDouble();
      it.pawLift = rng.nextBool() ? 1 : 0;
      it.eyes = rng.nextDouble();
      it.knead = rng.nextBool() ? 1 : 0;
      if (poses) {
        final k = rng.nextInt(3);
        pose = k == 0
            ? RigPose.ground
            : RigPose(angle: angle, legsFree: 1, tailFree: k == 1 ? 1.0 : 0.25, struggle: rng.nextDouble());
      }
    }
    final carried = poses && pose.legsFree > 0;
    if (carried) {
      // 身體像鐘擺一樣大幅擺動（比真的被抱著還劇烈）
      omega += (-30 * math.sin(angle - 1.4) - 0.8 * omega) / 60;
      angle += omega / 60;
      pose = RigPose(angle: angle, legsFree: pose.legsFree, tailFree: pose.tailFree, struggle: pose.struggle);
    } else {
      loco.update(1 / 60, it);
    }
    final r = rig.update(1 / 60, it, loco.x, carried ? 0 : loco.vx, pose: pose);
    final pts = _points(r);
    for (final p in pts) {
      expect(p.x.isFinite && p.y.isFinite, isTrue);
    }
    if (prev != null && prevTip != null && frame > 2) {
      for (var i = 0; i < pts.length; i++) {
        final d = pts[i].dist(prev[i]);
        if (d > worst) {
          worst = d;
          worstWhere = '${_names[i]} @frame $frame posture=${it.posture.name} legsFree=${pose.legsFree} '
              'facing=${r.facing.toStringAsFixed(2)} vx=${loco.vx.toStringAsFixed(1)}';
        }
      }
      worstTip = math.max(worstTip, r.tail.last.dist(prevTip));
    }
    prev = pts;
    prevTip = r.tail.last;
  }
  // ignore: avoid_print
  print('worst: $worstWhere | foot speed limiter used ${rig.footClamps}x, max excess ${rig.footClampMax.toStringAsFixed(2)}');
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
  test('骨架：亂切姿勢與目標，每幀位移都很小（畫面連續）', () {
    final (worst, tip) = _maxJump(poses: false);
    // ignore: avoid_print
    print('ground worst body=$worst tailTip=$tip');
    expect(worst, lessThan(3.5));
    expect(tip, lessThan(6.0));
  });

  test('骨架：在地上、被抱著、懸空之間亂切，也一樣連續', () {
    final (worst, tip) = _maxJump(poses: true, seed: 5);
    // ignore: avoid_print
    print('poses worst body=$worst tailTip=$tip');
    expect(worst, lessThan(3.5));
    expect(tip, lessThan(6.0));
  });

  test('rebase：身體座標平移後，之後每一幀都只是整體平移（看不出差別）', () {
    final a = PetRig(50), b = PetRig(50);
    final la = Locomotion()..x = 50, lb = Locomotion()..x = 50;
    final it = MotorIntent();
    const dx = 37.0;
    for (var frame = 0; frame < 600; frame++) {
      if (frame % 60 == 0) {
        it.reset();
        it.posture = Posture.values[frame ~/ 60 % Posture.values.length];
        it.targetX = 30 + (frame % 120 == 0 ? 40 : 0);
      }
      if (frame == 200) {
        lb.x += dx;
        b.rebase(dx);
      }
      final itB = MotorIntent()
        ..posture = it.posture
        ..targetX = it.targetX == null ? null : it.targetX! + (frame >= 200 ? dx : 0);
      la.update(1 / 60, it);
      lb.update(1 / 60, itB);
      final ra = a.update(1 / 60, it, la.x, la.vx);
      final rb = b.update(1 / 60, itB, lb.x, lb.vx);
      if (frame >= 200) {
        final pa = _points(ra), pb = _points(rb);
        for (var i = 0; i < pa.length; i++) {
          expect(pb[i].x - pa[i].x, closeTo(dx, 1e-6), reason: '${_names[i]} @$frame');
          expect(pb[i].y, closeTo(pa[i].y, 1e-6));
        }
        expect(rb.tail.last.x - ra.tail.last.x, closeTo(dx, 1e-6));
      }
    }
  });
}
