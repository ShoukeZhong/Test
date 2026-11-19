import '../anim/rig.dart';
import '../sim/cat.dart';
import '../sim/profile.dart';
import '../sim/simulator.dart';
import '../sim/util.dart';
import 'pet_body.dart';

/// 一隻貓在螢幕世界裡的一幀：行為 → 骨架（身體座標）→ 身體物理（放到世界）。
/// 懸浮視窗和單元測試共用這一份，順序完全一樣。
class PetWorld {
  PetWorld({required Traits traits, required double minX, required double maxX, required this.topY, double? startX, int? seed})
      : sim = Simulator(traits: traits, seed: seed) {
    sim.loco
      ..minX = minX
      ..maxX = maxX
      ..x = startX ?? (minX + maxX) / 2;
    rig = PetRig(sim.loco.x);
  }

  final Simulator sim;
  late final PetRig rig;
  final PetBody body = PetBody();
  double topY;

  RigFrame? frame;
  Placement placement = const Placement(V2.zero, V2.zero, 0);

  double get minX => sim.loco.minX;
  double get maxX => sim.loco.maxX;

  void setBounds(double minX, double maxX, double topY) {
    sim.loco
      ..minX = minX
      ..maxX = maxX;
    this.topY = topY;
  }

  /// 整個世界換比例（例如貓變大變小）：身體座標一起平移，畫面不跳
  void shiftTo(double newX) {
    rig.rebase(newX - sim.loco.x);
    sim.loco.x = newX;
  }

  void step(double dt) {
    sim.carried = body.carried;
    sim.step(dt);
    final it = sim.brain.intent;
    final f = rig.update(dt, it, sim.loco.x, sim.loco.vx,
        fear: sim.needs.fear, brightness: sim.stim.brightness, pose: body.pose(struggle: it.struggle));
    placement = body.update(dt, f, struggle: it.struggle, minX: minX, maxX: maxX, topY: topY);
    frame = f;
    if (body.landImpact >= 0) sim.landImpact = body.landImpact;
    if (body.rebaseDx != 0) {
      // 這一幀已經用舊的身體座標算好畫面；下一幀起改用對齊後的座標
      sim.loco.x += body.rebaseDx;
      rig.rebase(body.rebaseDx);
      sim.loco.vx = clampD(body.landVx, -CatBody.runSpeed, CatBody.runSpeed);
    }
  }

  void grab(V2 fingerWorld) {
    final f = frame;
    if (f != null) body.grab(fingerWorld, f);
  }
}
