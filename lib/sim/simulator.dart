import 'dart:math' as math;

import 'brain.dart';
import 'life.dart';
import 'motor.dart';
import 'physiology.dart';
import 'state.dart';
import 'stimuli.dart';
import 'util.dart';
import 'world.dart';

/// 媽媽：新生到斷奶期間陪在窩邊，斷奶完成後走出畫面。
class MotherAgent {
  final Locomotion loco = Locomotion()
    ..x = World.nestX - 7
    ..clampToRoom = false;
  final MotorIntent intent = MotorIntent();
  bool gone = false;
  bool leaving = false;
  double t = 0;
  double nextLick = 6;

  void update(double dt, LifeInfo kitten, double kittenX, math.Random rng) {
    t += dt;
    intent.reset();
    if (gone) return;
    if (!kitten.motherPresent || kitten.dead) {
      if (!leaving) {
        leaving = true;
        petLog('mother leaves');
      }
      intent.targetX = 125;
      intent.speed = 16;
      intent.tailUp = 0.6;
      loco.update(dt, intent, mobility: 1);
      if (loco.x > 120) gone = true;
      return;
    }
    // 躺在窩邊，偶爾抬頭舔舔孩子
    intent.posture = Posture.lie;
    intent.faceDir = 1.0;
    intent.eyes = 0.4;
    intent.breath = 0.8;
    nextLick -= dt;
    if (nextLick < 0) {
      intent.posture = Posture.loaf;
      intent.headDip = 0.6;
      intent.gazeX = kittenX;
      intent.gazeY = 1;
      intent.eyes = 0.8;
      if (nextLick < -3) nextLick = 10 + rng.nextDouble() * 20;
    }
    loco.update(dt, intent, mobility: 1);
  }
}

/// 把生理、行為、移動、世界物理串起來。UI 每幀呼叫 step()。
class Simulator {
  Simulator(this.s, this.w, {int? seed})
      : rng = math.Random(seed ?? (s.seed ^ DateTime.now().millisecondsSinceEpoch)) {
    brain = Brain(rng);
    final life = this.life;
    loco.x = life.motherPresent ? World.nestX + 4 : World.bedX;
    if (!life.motherPresent) mother.gone = true;
    if (s.dead) {
      brain.act = Act.dead;
    } else if (s.asleep || life.motherCares) {
      brain.act = life.motherPresent ? Act.nurse : Act.sleep;
      brain.phase = 1;
    }
  }

  final PetState s;
  final World w;
  final math.Random rng;
  final Stimuli stim = Stimuli();
  final Locomotion loco = Locomotion();
  final MotherAgent mother = MotherAgent();
  late final Brain brain;

  LifeInfo get life => Physiology.lifeOf(s);

  void step(double dtReal, int nowMs) {
    if (dtReal <= 0) return;
    final dtBio = dtReal * s.timeScale;
    if (s.timeScale >= 600) {
      // 開發用快轉：生理改用離線規則自動吃喝拉撒，動畫仍是真實速度
      CatchUp.run(s, w, dtBio, nowMs, rng);
    } else {
      Physiology.tick(s, w, dtBio, asleep: brain.asleep, load: brain.load, nowMs: nowMs);
    }
    s.asleep = brain.asleep;
    s.lastUpdateEpochMs = nowMs;
    stim.sinceStroke += dtReal;
    final l = life;
    brain.update(dtReal, BrainCtx(s, w, stim, loco, l, nowMs));
    loco.update(dtReal, brain.intent, mobility: l.mobility);
    mother.update(dtReal, l, loco.x, rng);
    w.update(dtReal);
    stim.clearOneShots();
  }

  /// App 關著的時間：用離線規則補算
  CatchUpReport catchUpTo(int nowMs) {
    final realSec = (nowMs - s.lastUpdateEpochMs) / 1000.0;
    if (realSec < 2) return CatchUpReport();
    final rep = CatchUp.run(s, w, realSec * s.timeScale, nowMs, rng);
    s.lastUpdateEpochMs = nowMs;
    petLog('catch-up ${realSec.toStringAsFixed(0)}s real -> $rep');
    if (s.dead) brain.act = Act.dead;
    return rep;
  }
}
