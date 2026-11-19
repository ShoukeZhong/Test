import 'dart:math' as math;

import 'cat.dart';
import 'profile.dart';
import 'util.dart';

/// 會影響行為的內在狀態（0 = 滿足，1 = 很強烈）。
/// 第一版不做飢餓、口渴、排泄、健康和壽命：這些只決定「牠現在想做什麼」，不會生病或死亡。
class Needs {
  double fatigue = 0.4;
  double boredom = 0.3;
  double loneliness = 0.3;
  double fear = 0;

  void clampAll() {
    fatigue = clampD(fatigue, 0, 1);
    boredom = clampD(boredom, 0, 1);
    loneliness = clampD(loneliness, 0, 1);
    fear = clampD(fear, 0, 1);
  }

  /// 每幀更新。睡眠恢復速度固定，清醒時累積速度由「一天睡多少比例」反推，
  /// 這樣長時間下來睡眠比例會接近 [CatBody.sleepFraction]。
  void tick(double dt, Traits t, {required bool asleep, double load = 0}) {
    if (dt <= 0) return;
    final recover = 1 / (2.5 * kHour) * (0.75 + 0.5 * t.activity); // 〔估〕
    if (asleep) {
      fatigue -= dt * recover;
    } else {
      const f = CatBody.sleepFraction;
      fatigue += dt * recover * f / (1 - f) * (0.85 + 0.3 * (1 - t.activity)) * (1 + 2 * load);
      boredom += dt / (3 * kHour) * (0.6 + 0.8 * t.activity); // 〔估〕
    }
    loneliness += dt / (5 * kHour) * (0.5 + t.sociability); // 〔估〕
    fear *= math.exp(-dt / 45); // 恐懼約 45 秒消退一大半〔估〕
    clampAll();
  }
}
