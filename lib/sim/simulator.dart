import 'dart:math' as math;

import 'brain.dart';
import 'motor.dart';
import 'needs.dart';
import 'profile.dart';
import 'stimuli.dart';

/// 把內在狀態、行為、移動串起來。懸浮視窗每幀呼叫 step()。
class Simulator {
  Simulator({required this.traits, int? seed}) : rng = math.Random(seed ?? DateTime.now().microsecondsSinceEpoch) {
    brain = Brain(rng);
    needs.fatigue = 0.25 + rng.nextDouble() * 0.4;
  }

  Traits traits;
  final math.Random rng;
  final Needs needs = Needs();
  final Stimuli stim = Stimuli();
  final Locomotion loco = Locomotion();
  late final Brain brain;

  /// 被抱著或在空中：位置交給 PetBody 的物理，自己不走路
  bool carried = false;

  /// 由 PetBody 在落地那一幀設定（撞擊速度），step() 用完就清掉
  double landImpact = -1;

  void step(double dt) {
    if (dt <= 0) return;
    needs.tick(dt, traits, asleep: brain.asleep, load: brain.load);
    stim.sinceStroke += dt;
    brain.update(dt, BrainCtx(needs, traits, stim, loco, carried: carried, landImpact: landImpact));
    if (!carried) loco.update(dt, brain.intent);
    landImpact = -1;
    stim.clearOneShots();
  }
}
