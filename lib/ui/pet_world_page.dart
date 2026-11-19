import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../anim/pet_painter.dart';
import '../anim/rig.dart';
import '../sense/camera_sensor.dart';
import '../sense/mic_sensor.dart';
import '../sim/brain.dart';
import '../sim/life.dart';
import '../sim/simulator.dart';
import '../sim/state.dart';
import '../sim/stimuli.dart';
import '../sim/util.dart';
import '../sim/world.dart';
import 'scene_painter.dart';
import 'setup_page.dart';
import 'storage.dart';

class _Touch {
  _Touch(this.id, this.mode, this.pos, this.ms);
  final int id;
  String mode;
  Offset pos;
  final int ms;
  double moved = 0;
  int lastMs = 0;
  V2 vel = V2.zero;
}

/// 寵物的世界：沒有按鈕，只有摸、拖、說話、在鏡頭前揮手。
class PetWorldPage extends StatefulWidget {
  const PetWorldPage({super.key, required this.state, required this.world});
  final PetState state;
  final World world;

  @override
  State<PetWorldPage> createState() => _PetWorldPageState();
}

class _PetWorldPageState extends State<PetWorldPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Simulator sim;
  late final PetRig rig;
  late final PetRig motherRig;
  late final SceneModel scene;
  late final MicSensor mic;
  late final CameraSensor cam;
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final math.Random _rng = math.Random();
  final Map<int, _Touch> _touches = {};
  Duration? _last;
  Size _size = Size.zero;
  double _saveT = 0, _logT = 0, _purrT = 0, _threeT = 0, _strokeLogT = 0;
  bool _devOpen = false;
  bool _swatBuzzed = false;
  bool _sensorsStarted = false;

  PetState get s => sim.s;
  World get w => sim.w;
  Stimuli get stim => sim.stim;

  @override
  void initState() {
    super.initState();
    sim = Simulator(widget.state, widget.world);
    sim.catchUpTo(DateTime.now().millisecondsSinceEpoch);
    rig = PetRig(s.species, sim.loco.x);
    motherRig = PetRig(s.species, sim.mother.loco.x);
    final coats = coatsOf(s.species);
    scene = SceneModel(s.species, coats[s.coat % coats.length], coats[(s.coat + 1) % coats.length])..world = w;
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _ticker = createTicker(_tick)..start();
    mic = MicSensor(stim);
    cam = CameraSensor(stim);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSensors());
  }

  Future<void> _startSensors() async {
    if (_sensorsStarted || s.dead) return;
    _sensorsStarted = true;
    await mic.start();
    await cam.start();
  }

  Future<void> _stopSensors() async {
    _sensorsStarted = false;
    await mic.stop();
    await cam.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final rep = sim.catchUpTo(DateTime.now().millisecondsSinceEpoch);
      if (rep.bioSec > 0) petLog('resume: $rep');
      _last = null;
      _startSensors();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      Store.save(s, w);
      _stopSensors();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    Store.save(s, w);
    _stopSensors();
    mic.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------- 每一幀 ----------------
  void _tick(Duration elapsed) {
    final dt = _last == null ? 1 / 60 : clampD((elapsed - _last!).inMicroseconds / 1e6, 0, 0.1);
    _last = elapsed;
    final now = DateTime.now().millisecondsSinceEpoch;
    final wasDead = s.dead;
    sim.step(dt, now);
    final life = sim.life;
    final hour = DateTime.now().hour + DateTime.now().minute / 60;
    scene.hour = hour;
    final daylight = (hour >= 7 && hour <= 18) ? 0.8 : 0.25;

    scene.pet = rig.update(dt, sim.brain.intent, sim.loco.x, sim.loco.vx, life,
        fear: s.needs.fear, brightness: stim.cameraOn ? stim.brightness : daylight);
    if (!sim.mother.gone) {
      final ml = LifeInfo(s.info, 4 * kYear, 15 * kYear, false);
      scene.mother = motherRig.update(dt, sim.mother.intent, sim.mother.loco.x, sim.mother.loco.vx, ml);
      scene.motherVisible = true;
    } else {
      scene.motherVisible = false;
    }
    scene.ageDays = life.days;
    scene.dead = s.dead;
    if (s.dead) scene.deadFade = math.min(1.0, scene.deadFade + dt / 6);

    _updateShelf(dt);
    _updateParticles(dt);
    _haptics(dt);

    if (_touches.length >= 3) {
      _threeT += dt;
      if (_threeT > 1.2 && !_devOpen) _openDev();
    } else {
      _threeT = 0;
    }

    _saveT += dt;
    if (_saveT > 20 || (!wasDead && s.dead)) {
      _saveT = 0;
      Store.save(s, w);
      if (s.dead) _stopSensors();
    }
    _logT += dt;
    if (_logT > 3 && _size != Size.zero) {
      _logT = 0;
      final v = WorldView(_size);
      final r = scene.pet;
      final sp = r == null ? Offset.zero : v.p(V2.lerp(r.hip, r.shoulder, 0.5));
      final dpr = View.of(context).devicePixelRatio;
      final n = s.needs;
      petLog('tick act=${sim.brain.act.name} stage=${life.stage.name} days=${life.days.toStringAsFixed(2)} '
          'x=${sim.loco.x.toStringAsFixed(1)} screen=${(sp.dx * dpr).round()},${(sp.dy * dpr).round()} '
          'hunger=${n.hunger.toStringAsFixed(2)} thirst=${n.thirst.toStringAsFixed(2)} fatigue=${n.fatigue.toStringAsFixed(2)} '
          'health=${s.health.toStringAsFixed(2)} mic=${stim.micOn} cam=${stim.cameraOn} motion=${stim.motion.toStringAsFixed(2)}');
    }
    _frame.value++;
    if (wasDead != s.dead) setState(() {});
  }

  void _haptics(double dt) {
    if (stim.touchingPet && sim.brain.intent.purr) {
      _purrT += dt;
      if (_purrT > 0.09) {
        _purrT = 0;
        HapticFeedback.selectionClick(); // 手指摸著才感覺得到呼嚕
      }
    }
    final swat = sim.brain.act == Act.petted && sim.brain.phase == 9;
    if (swat && !_swatBuzzed) HapticFeedback.heavyImpact();
    _swatBuzzed = swat;
  }

  // ---------------- 飼料袋、水壺 ----------------
  void _updateShelf(double dt) {
    if (_size == Size.zero) return;
    final v = WorldView(_size);
    final k = 1 - math.exp(-dt * 10);
    final bagHeld = _touches.values.any((t) => t.mode == 'bag');
    final jugHeld = _touches.values.any((t) => t.mode == 'jug');
    final bagHome = ScenePainter.bagRect(_size).center, jugHome = ScenePainter.jugRect(_size).center;
    if (!bagHeld) scene.bagPos = Offset.lerp(scene.bagPos == Offset.zero ? bagHome : scene.bagPos, bagHome, k)!;
    if (!jugHeld) scene.jugPos = Offset.lerp(scene.jugPos == Offset.zero ? jugHome : scene.jugPos, jugHome, k)!;

    final foodBowl = v.p(const V2(World.foodX, 3));
    final waterBowl = v.p(const V2(World.waterX, 3));
    final bagPour = bagHeld && (scene.bagPos.dx - foodBowl.dx).abs() < 7 * v.s && scene.bagPos.dy < foodBowl.dy - 20;
    final jugPour = jugHeld && (scene.jugPos.dx - waterBowl.dx).abs() < 7 * v.s && scene.jugPos.dy < waterBowl.dy - 20;
    scene.bagTilt = lerpD(scene.bagTilt, bagPour ? 2.2 : 0, k);
    scene.jugTilt = lerpD(scene.jugTilt, jugPour ? -1.9 : 0, k);
    if (bagPour && scene.bagTilt > 1.5) {
      if (w.food < 1) {
        w.pourFood(dt * 0.25);
        for (var i = 0; i < 2; i++) {
          scene.particles.add(Particle(scene.bagPos + Offset((_rng.nextDouble() - 0.5) * 10, 20),
              Offset((_rng.nextDouble() - 0.5) * 30, 50), const Color(0xFF9B5E2E), 2, 2.2));
        }
      }
    }
    if (jugPour && scene.jugTilt < -1.3) {
      if (w.water < 1) {
        w.pourWater(dt * 0.3);
        for (var i = 0; i < 3; i++) {
          scene.particles.add(Particle(scene.jugPos + Offset(-14 + (_rng.nextDouble() - 0.5) * 4, 12),
              Offset((_rng.nextDouble() - 0.5) * 10, 80), const Color(0xFF6FB3E0), 2, 2.4));
        }
      }
    }
  }

  void _updateParticles(double dt) {
    if (_size == Size.zero) return;
    final floor = WorldView(_size).floorY;
    for (final p in scene.particles) {
      p.vel = p.vel + Offset(0, 900 * dt);
      p.pos = p.pos + p.vel * dt;
      p.life -= dt;
    }
    scene.particles.removeWhere((p) => p.life <= 0 || p.pos.dy > floor - 8);
  }

  // ---------------- 觸控：判斷摸到哪裡 ----------------
  BodyRegion? _hitPet(V2 p) {
    final r = scene.pet;
    if (r == null || s.dead) return null;
    final pad = 1.3 + (1 - r.growth) * 1.2; // 小時候身體小，判定放寬
    final rel = p - r.head;
    if (rel.length < r.headR * 1.25 * pad) {
      final front = rel.x * (r.facing >= 0 ? 1 : -1) > 0;
      return (rel.y < 0 && (front || r.headTurn > 0.6)) ? BodyRegion.cheek : BodyRegion.head;
    }
    for (var i = 0; i <= 10; i++) {
      final u = i / 10;
      final pt = V2.lerp(V2.lerp(r.hip, r.spineCtrl, u), V2.lerp(r.spineCtrl, r.shoulder, u), u);
      if (p.dist(pt) < r.torsoT * 0.75 * pad) {
        return p.y < pt.y - r.torsoT * 0.15 ? BodyRegion.belly : BodyRegion.back;
      }
    }
    for (final t in r.tail) {
      if (p.dist(t) < math.max(2.0, r.tailW0 * 1.6) * pad) return BodyRegion.tail;
    }
    for (final l in r.legs) {
      if (p.dist(l.knee) < r.torsoT * 0.45 * pad || p.dist(l.foot) < r.torsoT * 0.45 * pad) return BodyRegion.legs;
    }
    return null;
  }

  bool _inToilet(V2 p) => (p.x - World.toiletX).abs() < World.toiletHalfW + 2 && p.y < 9;

  void _down(PointerDownEvent e) {
    if (_size == Size.zero) return;
    final v = WorldView(_size);
    final wp = v.w(e.localPosition);
    final t = _Touch(e.pointer, 'none', e.localPosition, DateTime.now().millisecondsSinceEpoch)..lastMs = DateTime.now().millisecondsSinceEpoch;
    _touches[e.pointer] = t;
    if (_touches.length > 1) return;
    if (s.dead) return;
    if (ScenePainter.bagRect(_size).inflate(14).contains(e.localPosition) && (scene.bagPos - ScenePainter.bagRect(_size).center).distance < 30) {
      t.mode = 'bag';
    } else if (ScenePainter.jugRect(_size).inflate(14).contains(e.localPosition) && (scene.jugPos - ScenePainter.jugRect(_size).center).distance < 30) {
      t.mode = 'jug';
    } else if (wp.dist(V2(w.ball.x, w.ball.y + Ball.r)) < Ball.r * 2.4) {
      t.mode = 'ball';
      w.ball.held = true;
    } else if (_hitPet(wp) != null) {
      t.mode = 'pet';
      stim.touchingPet = true;
    } else if (_inToilet(wp) || w.floor.any((x) => (x.x - wp.x).abs() < 5 && wp.y < 8)) {
      t.mode = 'scoop';
      _scoop(wp);
    } else if (wp.y < 16) {
      t.mode = 'finger';
      stim.fingerX = clampD(wp.x, World.minX, World.maxX);
    }
    petLog('touch down mode=${t.mode}');
  }

  void _scoop(V2 wp) {
    final ok = _inToilet(wp) ? w.scoopNear(wp.x, inToilet: true, range: 9) : w.scoopNear(wp.x, range: 5);
    if (ok) {
      HapticFeedback.lightImpact();
      petLog('scooped (toilet=${w.toilet.length} floor=${w.floor.length})');
    }
  }

  void _move(PointerMoveEvent e) {
    final t = _touches[e.pointer];
    if (t == null || _size == Size.zero) return;
    final v = WorldView(_size);
    final now = DateTime.now().millisecondsSinceEpoch;
    final dt = math.max(1, now - t.lastMs) / 1000.0;
    final a = v.w(t.pos), b = v.w(e.localPosition);
    final dist = a.dist(b);
    t.vel = V2.lerp(t.vel, (b - a) * (1 / dt), 0.5);
    t.moved += dist;
    t.pos = e.localPosition;
    t.lastMs = now;
    switch (t.mode) {
      case 'bag':
        scene.bagPos = e.localPosition;
      case 'jug':
        scene.jugPos = e.localPosition;
      case 'ball':
        w.ball.x = clampD(b.x, World.minX, World.maxX);
        w.ball.y = math.max(0.0, b.y - Ball.r);
      case 'pet':
        final region = _hitPet(b);
        stim.touchingPet = region != null;
        if (region != null && dist > 0.02) {
          stim.strokeRegion = region;
          stim.strokeSpeed = lerpD(stim.strokeSpeed, dist / dt, 0.3);
          stim.sinceStroke = 0;
          _strokeLogT += dt;
          if (_strokeLogT > 0.5) {
            _strokeLogT = 0;
            petLog('touch stroke region=${region.name} speed=${stim.strokeSpeed.toStringAsFixed(0)}');
          }
        }
      case 'scoop':
        _scoop(b);
      case 'finger':
        stim.fingerX = clampD(b.x, World.minX, World.maxX);
        stim.fingerSpeed = lerpD(stim.fingerSpeed, (b.x - a.x).abs() / dt, 0.3);
    }
  }

  void _up(PointerEvent e) {
    final t = _touches.remove(e.pointer);
    if (t == null) return;
    final ms = DateTime.now().millisecondsSinceEpoch - t.ms;
    switch (t.mode) {
      case 'pet':
        if (t.moved < 0.8 && ms < 260) {
          stim.poke = true;
          petLog('touch poke');
        }
        stim.touchingPet = false;
      case 'ball':
        w.ball.held = false;
        w.ball.vx = clampD(t.vel.x, -160, 160);
        w.ball.vy = clampD(t.vel.y, -40, 160);
        petLog('ball thrown vx=${w.ball.vx.toStringAsFixed(0)}');
      case 'finger':
        stim.fingerX = null;
        stim.fingerSpeed = 0;
    }
  }

  // ---------------- 開發者面板（三指長按） ----------------
  Future<void> _openDev() async {
    _devOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final life = sim.life;
        final n = s.needs;
        String pct(double x) => '${(x * 100).round()}';
        return Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(shrinkWrap: true, children: [
            Text('開發者面板', style: Theme.of(ctx).textTheme.titleMedium),
            Text('行為：${actLabel[sim.brain.act]}　階段：${lifeStageLabel[life.stage]}　年齡：${_ageText(life)}'),
            Text('壽命設定：${(s.lifespanSec / kYear).toStringAsFixed(1)} 年　健康：${pct(s.health)}'),
            Text('飢餓 ${pct(n.hunger)}　口渴 ${pct(n.thirst)}　膀胱 ${pct(n.bladder)}　腸 ${pct(n.bowel)}'),
            Text('疲倦 ${pct(n.fatigue)}　無聊 ${pct(n.boredom)}　寂寞 ${pct(n.loneliness)}　害怕 ${pct(n.fear)}'),
            Text('麥克風：${stim.micOn ? '開' : '關'}　鏡頭：${stim.cameraOn ? '開' : '關'}　亮度 ${pct(stim.brightness)}'),
            const SizedBox(height: 8),
            const Text('時間倍率（只用來測試，正常應為 1×）'),
            Wrap(spacing: 8, children: [
              for (final k in [1.0, 60.0, 1440.0, 86400.0])
                ChoiceChip(
                  label: Text(k == 1 ? '1×' : k == 60 ? '60×' : k == 1440 ? '1 分鐘 = 1 天' : '1 秒 = 1 天'),
                  selected: s.timeScale == k,
                  onSelected: (_) => setSheet(() => s.timeScale = k),
                ),
            ]),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await Store.clear();
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                _restart();
              },
              child: const Text('刪除這隻寵物，重新開始'),
            ),
          ]),
        );
      }),
    );
    _devOpen = false;
  }

  void _restart() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const SetupPage()));
  }

  String _ageText(LifeInfo life) {
    final d = life.days;
    if (d < 1) return '${(d * 24).toStringAsFixed(0)} 小時';
    if (d < 60) return '${d.toStringAsFixed(0)} 天';
    if (d < 730) return '${(d / 30.4).toStringAsFixed(0)} 個月';
    return '${life.years.toStringAsFixed(1)} 歲';
  }

  @override
  Widget build(BuildContext context) {
    final life = sim.life;
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, box) {
        _size = Size(box.maxWidth, box.maxHeight);
        return Stack(children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: CustomPaint(painter: ScenePainter(scene, _frame), size: Size.infinite),
            ),
          ),
          // 很淡的名字和年齡（不是按鈕）
          Positioned(
            left: 16,
            top: MediaQuery.paddingOf(context).top + 10,
            child: IgnorePointer(
              child: ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (_, __, ___) => Text(
                  '${s.name}　${_ageText(sim.life)}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13, shadows: const [Shadow(blurRadius: 4)]),
                ),
              ),
            ),
          ),
          if (s.dead) _memorial(context, life),
        ]);
      }),
    );
  }

  Widget _memorial(BuildContext context, LifeInfo life) {
    String date(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      return '${d.year}/${d.month}/${d.day}';
    }

    final died = s.events.where((e) => e.code == 'died').toList();
    return Align(
      alignment: Alignment.bottomCenter,
      child: Card(
        margin: const EdgeInsets.all(16),
        color: Colors.black.withValues(alpha: 0.72),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s.name}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            Text('${date(s.bornEpochMs)} – ${died.isEmpty ? '' : date(died.last.epochMs)}　${_ageText(life)}　${s.deathCause ?? ''}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              child: ListView(children: [
                for (final e in s.events)
                  Text('${date(e.epochMs)}　${e.text}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                await Store.clear();
                _restart();
              },
              child: const Text('迎接新的生命'),
            ),
          ]),
        ),
      ),
    );
  }
}
