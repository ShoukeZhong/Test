import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_overlay/anim/rig.dart';
import 'package:pet_overlay/overlay/pet_body.dart';
import 'package:pet_overlay/overlay/pet_world.dart';
import 'package:pet_overlay/sim/profile.dart';
import 'package:pet_overlay/sim/util.dart';

PetWorld _world({String desc = '超級黏人、淡定', int seed = 1}) =>
    PetWorld(traits: compileTraits(desc).$1, minX: 20, maxX: 180, topY: 300, startX: 100, seed: seed);

List<V2> _bodyPoints(RigFrame r) => [
      r.head,
      r.hip,
      r.shoulder,
      for (final l in r.legs) ...[l.knee, l.foot],
    ];

/// 一邊跑一邊檢查：(1) 不穿過地板 (2) 扣掉「整隻貓的平移＋旋轉」後，任何身體點每幀都不會跳
class _Watch {
  List<V2>? prev;
  V2? prevCom;
  double prevAngle = 0;
  double worstRel = 0;
  String worstWhere = '';
  double lowest = double.infinity;

  void check(PetWorld w, String phase) {
    final f = w.frame!, p = w.placement;
    final pts = _bodyPoints(f).map(p.map).toList();
    final com = p.map(f.com);
    // 「不穿過地板」只檢查抱著和空中（在地上時腳本來就踩在地板上）
    if (w.body.mode != CarryMode.ground) lowest = math.min(lowest, PetBody.lowestY(f, p));
    if (prev != null && prevCom != null) {
      final da = wrapAngle(p.angle - prevAngle);
      for (var i = 0; i < pts.length; i++) {
        final predicted = com + (prev![i] - prevCom!).rotate(da);
        final rel = (pts[i] - predicted).length;
        if (rel > worstRel) {
          worstRel = rel;
          worstWhere = 'point $i during $phase (mode=${w.body.mode.name})';
        }
      }
    }
    prev = pts;
    prevCom = com;
    prevAngle = p.angle;
  }
}

void main() {
  test('抱起來：身體會晃到「質心在手指正下方」，而且不會穿過地板', () {
    final w = _world();
    final watch = _Watch();
    for (var i = 0; i < 60; i++) {
      w.step(1 / 60);
      watch.check(w, 'stand');
    }
    final f = w.frame!;
    final back = w.placement.map(V2.lerp(f.hip, f.shoulder, 0.5) + V2(0, f.torsoT * 0.3));
    w.grab(back);
    expect(w.body.mode, CarryMode.held);
    // 一秒內把手指往上提到離地 60 單位
    for (var i = 0; i < 60; i++) {
      w.body.moveFinger(V2(back.x, back.y + (60 - back.y) * (i + 1) / 60));
      w.step(1 / 60);
      watch.check(w, 'lift');
    }
    for (var i = 0; i < 240; i++) {
      w.step(1 / 60);
      watch.check(w, 'hang');
    }
    final g = w.frame!, p = w.placement;
    final com = p.map(g.com), hold = p.map(g.holdPoint);
    // ignore: avoid_print
    print('hang angle=${w.body.angle.toStringAsFixed(2)} com-hold dx=${(com.x - hold.x).toStringAsFixed(2)} '
        'worstRel=${watch.worstRel.toStringAsFixed(2)} (${watch.worstWhere}) lowest=${watch.lowest.toStringAsFixed(2)}');
    expect((com.x - hold.x).abs(), lessThan(1.0));
    expect(com.y, lessThan(hold.y));
    expect(p.map(g.head).y, greaterThan(p.map(g.hip).y)); // 頭在上
    expect(watch.lowest, greaterThan(-0.05));
    expect(watch.worstRel, lessThan(4));
  });

  test('放手：掉下來、翻正、四腳著地，落地後慢慢回到正常', () {
    final w = _world(seed: 2);
    for (var i = 0; i < 30; i++) {
      w.step(1 / 60);
    }
    final f = w.frame!;
    final start = w.placement.map(f.holdPoint);
    w.grab(start);
    for (var i = 0; i < 90; i++) {
      w.body.moveFinger(V2(start.x, start.y + (120 - start.y) * math.min(1, (i + 1) / 60)));
      w.step(1 / 60);
    }
    w.body.release();
    var t = 0.0;
    double? landT;
    var tiltAtLand = 0.0;
    var impact = 0.0;
    while (t < 3) {
      w.step(1 / 60);
      t += 1 / 60;
      if (landT == null && w.body.mode == CarryMode.ground) {
        landT = t;
        tiltAtLand = wrapAngle(w.placement.angle);
        impact = w.sim.landImpact >= 0 ? w.sim.landImpact : w.body.landImpact;
      }
    }
    // ignore: avoid_print
    print('landed after ${landT?.toStringAsFixed(2)}s tilt=${tiltAtLand.toStringAsFixed(2)} impact=${impact.toStringAsFixed(0)}');
    expect(landT, isNotNull);
    expect(landT!, inInclusiveRange(0.2, 1.2)); // 從約 1.5 m（貓的比例）落下
    expect(tiltAtLand.abs(), lessThan(0.35)); // 翻正反射：腳先著地
    expect(impact, greaterThan(150));
    expect(w.body.settled, isTrue);
    expect(w.placement.angle.abs(), lessThan(0.01));
    expect(w.placement.pivotW.y.abs(), lessThan(0.05));
  });

  test('甩出去、撞牆、落地、走開：整段畫面連續，位置不跳', () {
    final w = _world(desc: '很膽小', seed: 3);
    final watch = _Watch();
    for (var i = 0; i < 30; i++) {
      w.step(1 / 60);
      watch.check(w, 'stand');
    }
    final f = w.frame!;
    var finger = w.placement.map(f.holdPoint);
    w.grab(finger);
    // 提起來，再快速往右甩（約 300 單位/秒）
    for (var i = 0; i < 150; i++) {
      final vx = i >= 135 ? 300.0 : 0.0;
      final up = i < 60 ? 1.6 : 0.0;
      finger = V2(finger.x + vx / 60, finger.y + up);
      w.body.moveFinger(finger);
      w.step(1 / 60);
      watch.check(w, 'held');
    }
    w.body.release();
    var landed = false;
    for (var i = 0; i < 360; i++) {
      w.step(1 / 60);
      watch.check(w, landed ? 'after' : 'air');
      if (w.body.mode == CarryMode.ground) landed = true;
      final x = w.placement.map(w.frame!.com).x;
      expect(x, inInclusiveRange(20 - 30, 180 + 30));
    }
    // ignore: avoid_print
    print('throw worstRel=${watch.worstRel.toStringAsFixed(2)} (${watch.worstWhere}) lowest=${watch.lowest.toStringAsFixed(2)} '
        'act=${w.sim.brain.act.name}');
    expect(landed, isTrue);
    expect(watch.worstRel, lessThan(4));
    expect(watch.lowest, greaterThan(-1.5));
  });

  test('半空中接住', () {
    final w = _world(seed: 4);
    for (var i = 0; i < 30; i++) {
      w.step(1 / 60);
    }
    var finger = w.placement.map(w.frame!.holdPoint);
    w.grab(finger);
    for (var i = 0; i < 90; i++) {
      finger = V2(finger.x, math.min(200, finger.y + 3));
      w.body.moveFinger(finger);
      w.step(1 / 60);
    }
    w.body.release();
    for (var i = 0; i < 12; i++) {
      w.step(1 / 60);
    }
    expect(w.body.mode, CarryMode.air);
    final com = w.placement.map(w.frame!.com);
    w.grab(com);
    expect(w.body.mode, CarryMode.held);
    final watch = _Watch();
    for (var i = 0; i < 60; i++) {
      w.step(1 / 60);
      watch.check(w, 'caught');
    }
    expect(watch.worstRel, lessThan(4));
  });
}
