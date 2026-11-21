import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import '../anim/spring.dart';
import '../sim/cat.dart';
import '../sim/stimuli.dart' show BodyRegion;
import 'credits.dart';
import 'window_camera.dart';

/// 3D 可行性實驗：在懸浮視窗裡用 flutter_scene（Flutter GPU）畫一隻有骨架動畫的四足動物。
///
/// 替身模型是 Khronos glTF Sample Assets 的 Fox（見 assets/models/Fox.LICENSE.md），
/// 這次只驗證「流程」：透明背景、骨架動畫混合、程式逐幀改骨頭、影子、觸控判定、效能。
/// 位置、方向、速度都來自原本的 2D 模擬（行為層不變），這裡只負責「畫成 3D」。
class Pet3D {
  Pet3D._(this.scene, this._holder, this._fox, this._anims, this._clips, this._joints, this.k);

  static const asset = 'assets/models/Fox.glb';
  static const credit = foxCredit;

  // Fox 的尺寸（模型單位，glTF 原始座標）：尾巴根到鼻尖約 93；量測方法見 docs/SOURCES.md
  static const double _modelBody = 93;
  // Walk／Run 動畫原本對應的地面速度（模型單位／秒，由腳掌觸地時的後移速度估計）
  static const double _walkNatural = 110, _runNatural = 220;
  // 3/4 側面：身體朝前進方向，再往鏡頭轉 22°，看得出立體
  static const double _toCamera = 22 * math.pi / 180;

  final fs.Scene scene;
  final WindowCamera camera = WindowCamera();
  final fs.Node _holder, _fox;
  final Map<String, fs.Animation> _anims;
  final Map<String, fs.AnimationClip> _clips;
  final Map<String, fs.Node> _joints;

  /// 模型單位 → 世界單位
  final double k;

  final _HeadLook _look = _HeadLook();
  final Spring _yaw = Spring(-(math.pi / 2 - _toCamera));
  final Map<String, Spring> _w = {'Survey': Spring(1), 'Walk': Spring(0), 'Run': Spring(0)};
  double _phase = 0;

  /// Flutter GPU 沒開或這支手機不支援時會丟例外：呼叫端退回 2D。
  static Future<Pet3D> load() async {
    await fs.Scene.preload(); // 引擎 shader（含影子承接面）
    final scene = fs.Scene();
    final fox = await fs.Node.fromGlbAsset(asset);
    final holder = fs.Node()..add(fox);
    scene.add(holder);

    // 看不見的地板：只畫出影子，背景維持透明（其他 App 透得過來）
    scene.add(fs.Node(
      mesh: fs.Mesh(fs.PlaneGeometry(width: 4000, depth: 800), fs.ShadowCatcherMaterial(shadowIntensity: 0.45, aoStrength: 0.0)),
    ));
    scene.directionalLight = fs.DirectionalLight(
      direction: vm.Vector3(-0.25, -1.0, 0.35),
      intensity: 2.6,
      castsShadow: true,
      shadowCascadeCount: 1,
      shadowMapResolution: 1024,
    );

    final anims = <String, fs.Animation>{};
    final clips = <String, fs.AnimationClip>{};
    for (final name in ['Survey', 'Walk', 'Run']) {
      final a = fox.findAnimationByName(name);
      if (a == null) continue;
      anims[name] = a;
      clips[name] = fox.createAnimationClip(a)
        ..loop = true
        ..weight = name == 'Survey' ? 1 : 0
        ..play();
    }
    final joints = <String, fs.Node>{};
    for (final j in _jointNames) {
      final n = fox.getChildByName(j);
      if (n != null) joints[j] = n;
    }
    final p = Pet3D._(scene, holder, fox, anims, clips, joints, CatBody.bodyLength * 1.25 / _modelBody);
    joints['b_Head_05']?.addComponent(p._look);
    return p;
  }

  static const _jointNames = [
    'b_Hip_01', 'b_Spine01_02', 'b_Spine02_03', 'b_Neck_04', 'b_Head_05', //
    'b_RightUpperArm_06', 'b_RightForeArm_07', 'b_RightHand_08', //
    'b_LeftUpperArm_09', 'b_LeftForeArm_010', 'b_LeftHand_011', //
    'b_Tail01_012', 'b_Tail02_013', 'b_Tail03_014', //
    'b_LeftLeg01_015', 'b_LeftLeg02_016', 'b_LeftFoot01_017', 'b_LeftFoot02_018', //
    'b_RightLeg01_019', 'b_RightLeg02_020', 'b_RightFoot01_021', 'b_RightFoot02_022',
  ];
  static const _chains = {
    BodyRegion.back: ['b_Hip_01', 'b_Spine01_02', 'b_Spine02_03', 'b_Neck_04'],
    BodyRegion.tail: ['b_Tail01_012', 'b_Tail02_013', 'b_Tail03_014', '*tip'],
    BodyRegion.legs: [
      'b_RightUpperArm_06', 'b_RightForeArm_07', 'b_RightHand_08', '|', //
      'b_LeftUpperArm_09', 'b_LeftForeArm_010', 'b_LeftHand_011', '|', //
      'b_LeftLeg01_015', 'b_LeftLeg02_016', 'b_LeftFoot01_017', 'b_LeftFoot02_018', '|', //
      'b_RightLeg01_019', 'b_RightLeg02_020', 'b_RightFoot01_021', 'b_RightFoot02_022',
    ],
  };
  // 各部位粗細（模型單位，半徑）
  static const _radius = {BodyRegion.back: 13.0, BodyRegion.tail: 9.0, BodyRegion.legs: 5.0};

  /// 把這一幀的 2D 模擬結果套到 3D 模型上。
  /// [place]：身體座標 → 世界座標（2D 的 Placement，抱起來時會轉）；[bodyX]：身體中心在身體座標的 x。
  void update(
    double dt, {
    required vm.Matrix4 place,
    required double bodyX,
    required double facing,
    required double speed,
    required bool grounded,
    required bool asleep,
    required bool visible,
    vm.Vector3? lookAt,
  }) {
    // 方向：朝前進方向、稍微轉向鏡頭；轉身時經過正面（看起來像回頭看你）
    _yaw.update(-facing * (math.pi / 2 - _toCamera), 0.12, dt);
    _holder
      ..visible = visible
      ..localTransform = place.multiplied(vm.Matrix4.translationValues(bodyX, 0, 0))
          .multiplied(vm.Matrix4.rotationY(_yaw.x))
          .multiplied(vm.Matrix4.diagonal3Values(k, k, k));

    // 步態：依速度在 站／走／跑 之間混合；走和跑共用同一個步伐相位，換檔時腳不會亂掉
    final sp = speed.abs();
    var ws = 0.0, ww = 0.0, wr = 0.0;
    const walk = CatBody.walkSpeed, run = CatBody.runSpeed;
    if (!grounded || sp < 3) {
      ws = 1;
    } else if (sp < walk) {
      final t = (sp - 3) / (walk - 3);
      ws = 1 - t;
      ww = t;
    } else if (sp < run) {
      final t = (sp - walk) / (run - walk);
      ww = 1 - t;
      wr = t;
    } else {
      wr = 1;
    }
    _w['Survey']!.update(ws, 0.12, dt);
    _w['Walk']!.update(ww, 0.12, dt);
    _w['Run']!.update(wr, 0.12, dt);
    final sum = math.max(1e-3, _w.values.fold<double>(0, (a, s) => a + math.max(0.0, s.x)));
    for (final e in _clips.entries) {
      e.value.weight = math.max(0.0, _w[e.key]!.x) / sum;
    }
    final walkA = _anims['Walk'], runA = _anims['Run'];
    if (walkA != null && runA != null) {
      // 每秒幾個步伐循環 = 速度 ÷ 動畫原本的速度 ÷ 動畫長度（腳掌不打滑）
      final fWalk = math.max(sp, 6.0) / (_walkNatural * k) / walkA.endTime;
      final fRun = math.max(sp, 20.0) / (_runNatural * k) / runA.endTime;
      final mw = _w['Walk']!.x.clamp(0.0, 1.0), mr = _w['Run']!.x.clamp(0.0, 1.0);
      final f = (mw + mr) < 1e-3 ? 0.0 : (mw * fWalk + mr * fRun) / (mw + mr);
      _phase = (_phase + f * dt) % 1.0;
      _clips['Walk']!
        ..playbackTimeScale = 0
        ..playbackTime = _phase * walkA.endTime;
      _clips['Run']!
        ..playbackTimeScale = 0
        ..playbackTime = _phase * runA.endTime;
    }
    _clips['Survey']?.playbackTimeScale = asleep ? 0.12 : 1.0;

    // 程式逐幀改骨頭：頭轉向手指（疊在動畫上面）
    _look
      ..target = grounded && !asleep ? lookAt : null
      ..bodyForward = _forward();
  }

  /// 模型正面方向（世界座標，水平）
  vm.Vector3 _forward() => vm.Vector3(-math.sin(_yaw.x), 0, -math.cos(_yaw.x));

  vm.Vector3 _pos(String j) {
    if (j == '*tip') {
      final a = _pos('b_Tail02_013'), b = _pos('b_Tail03_014');
      return b + (b - a) * 0.9;
    }
    final n = _joints[j];
    return n == null ? _holder.globalTransform.getTranslation() : n.globalTransform.getTranslation();
  }

  vm.Vector3 _modelDir(double x, double y, double z) {
    final d = _holder.globalTransform.rotated3(vm.Vector3(x, y, -z)); // 匯入時 z 反轉：模型正面是 −z
    return d.normalized();
  }

  /// 頭的中心（比頭骨往鼻子方向一點）
  vm.Vector3 get headCenter => _pos('b_Head_05') + _modelDir(0, 0, 1) * (12 * k);

  /// 背的正中間、偏上
  vm.Vector3 get backPoint =>
      (_pos('b_Spine01_02') + _pos('b_Spine02_03')) * 0.5 + _modelDir(0, 1, 0) * (8 * k);

  /// 觸控判定（螢幕 dp）：骨頭位置投影到螢幕，量手指到各段骨頭的距離。
  /// flutter_scene 的 raycast 只用靜止姿勢判斷蒙皮網格，動起來會不準，所以自己用骨頭算。
  BodyRegion? hit(ui.Offset pt, {double pad = 1.3, double minDp = 9}) {
    double r(double modelR, vm.Vector3 at) => math.max(minDp, modelR * k * camera.s * camera.depthScale(at)) * pad;
    final hc = headCenter;
    final hs = camera.toScreen(hc);
    final rel = pt - hs;
    if (rel.distance < r(17, hc)) return rel.dy > r(17, hc) * 0.2 ? BodyRegion.cheek : BodyRegion.head;
    for (final region in [BodyRegion.back, BodyRegion.tail, BodyRegion.legs]) {
      final chain = _chains[region]!;
      for (var i = 0; i + 1 < chain.length; i++) {
        if (chain[i] == '|' || chain[i + 1] == '|') continue;
        final a3 = _pos(chain[i]), b3 = _pos(chain[i + 1]);
        final a = camera.toScreen(a3), b = camera.toScreen(b3);
        final (dist, c) = _segDist(pt, a, b);
        final rr = r(_radius[region]!, (a3 + b3) * 0.5);
        if (dist < rr) {
          if (region == BodyRegion.back) return pt.dy > c.dy + rr * 0.25 ? BodyRegion.belly : BodyRegion.back;
          return region;
        }
      }
    }
    return null;
  }

  /// 模型在螢幕上的外框（dp），給懸浮視窗跟著走
  ui.Rect screenBounds() {
    var l = double.infinity, t = double.infinity, rr = -double.infinity, b = -double.infinity;
    void add(vm.Vector3 p, double modelR) {
      final o = camera.toScreen(p);
      final rad = modelR * k * camera.s * camera.depthScale(p);
      l = math.min(l, o.dx - rad);
      rr = math.max(rr, o.dx + rad);
      t = math.min(t, o.dy - rad);
      b = math.max(b, o.dy + rad);
    }

    final head = _pos('b_Head_05');
    add(headCenter, 17);
    add(head + _modelDir(0, 0, 1) * (30 * k), 4); // 鼻尖
    add(head + _modelDir(0, 1, 0) * (19 * k), 5); // 耳朵
    for (final region in _chains.keys) {
      for (final j in _chains[region]!) {
        if (j != '|') add(_pos(j), _radius[region]!);
      }
    }
    return ui.Rect.fromLTRB(l, t, rr, b);
  }

  /// 依視窗位置更新相機；影子範圍要涵蓋到眼睛前方的貓
  void frame({required ui.Size screen, required double floorY, required double s, required ui.Rect window, vm.Vector2? eyeShift}) {
    camera.frame(screen: screen, floorY: floorY, s: s, window: window, eyeShift: eyeShift);
    scene.directionalLight?.shadowMaxDistance = camera.distance + 200;
  }

  Widget view({required bool active, double? maxFps}) => fs.SceneView(
        scene,
        camera: camera,
        autoTick: active,
        maxFrameRate: maxFps,
      );

  /// 手指到線段的距離與最近點
  static (double, ui.Offset) _segDist(ui.Offset p, ui.Offset a, ui.Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final t = len2 < 1e-9 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    final c = a + ab * t;
    return ((p - c).distance, c);
  }

  /// 測試用：骨頭有沒有都找到
  int get jointCount => _joints.length;
  List<String> get clipNames => _clips.keys.toList();
  fs.Node get model => _fox;
}

/// 頭轉向目標：在動畫算完之後（同一幀、骨頭還沒畫出來前）再疊一個轉動。
/// flutter_scene 先跑父節點的動畫播放器、再跑子節點的元件，所以掛在頭骨上的元件拿得到「動畫後」的姿勢。
class _HeadLook extends fs.Component {
  vm.Vector3? target;
  vm.Vector3 bodyForward = vm.Vector3(1, 0, 0);
  double _w = 0, _yaw = 0, _pitch = 0;

  @override
  void update(double deltaSeconds) {
    final dt = deltaSeconds.clamp(0.0, 0.1);
    final want = target;
    _w += ((want != null ? 1.0 : 0.0) - _w) * (1 - math.exp(-dt * 5));
    if (_w < 0.01) return;
    final n = node;
    final parent = n.parent;
    if (parent == null) return;
    final g = n.globalTransform.clone();
    final p = g.getTranslation();
    if (want != null) {
      final d = want - p;
      final f = bodyForward;
      var yawT = math.atan2(d.x, d.z) - math.atan2(f.x, f.z);
      while (yawT > math.pi) {
        yawT -= 2 * math.pi;
      }
      while (yawT < -math.pi) {
        yawT += 2 * math.pi;
      }
      final pitchT = math.atan2(d.y, math.sqrt(d.x * d.x + d.z * d.z));
      final a = 1 - math.exp(-dt * 8);
      _yaw += (yawT.clamp(-1.1, 1.1) - _yaw) * a;
      _pitch += (pitchT.clamp(-0.5, 0.6) - _pitch) * a;
    }
    final right = vm.Vector3(0, 1, 0).cross(bodyForward)..normalize();
    final q = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _yaw * _w) * vm.Quaternion.axisAngle(right, -_pitch * _w);
    final rot = vm.Matrix4.identity()..setRotation(q.asRotationMatrix());
    final delta = vm.Matrix4.translation(p).multiplied(rot).multiplied(vm.Matrix4.translation(-p));
    final inv = vm.Matrix4.zero();
    if (inv.copyInverse(parent.globalTransform) == 0) return;
    n.localTransform = inv.multiplied(delta).multiplied(g);
  }
}
