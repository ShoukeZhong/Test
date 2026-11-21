import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../anim/pet_painter.dart';
import '../anim/rig.dart';
import '../anim/spring.dart';
import '../sense/camera_sensor.dart';
import '../sense/mic_sensor.dart';
import '../sim/brain.dart';
import '../sim/cat.dart';
import '../sim/simulator.dart';
import '../sim/stimuli.dart';
import '../sim/util.dart';
import '../three/pet3d.dart';
import '../ui/storage.dart';
import 'pet_body.dart';
import 'pet_world.dart';
import 'window_bridge.dart';

/// 懸浮視窗的進入點（main.dart 的 overlayMain 會跑這個）
class OverlayPetApp extends StatelessWidget {
  const OverlayPetApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        color: Colors.transparent,
        home: Material(color: Colors.transparent, child: OverlayPet()),
      );
}

enum _Win { small, full }

enum _TouchMode { none, pet, grab, finger }

class OverlayPet extends StatefulWidget {
  const OverlayPet({super.key});

  @override
  State<OverlayPet> createState() => _OverlayPetState();
}

class _OverlayPetState extends State<OverlayPet> with SingleTickerProviderStateMixin {
  final WindowBridge bridge = WindowBridge();
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  late final Ticker _ticker;
  StreamSubscription<RawTouch>? _touchSub;
  StreamSubscription<dynamic>? _msgSub;
  StreamSubscription<bool>? _shownSub;

  ScreenMetrics m = ScreenMetrics.fallback;
  PetProfile profile = PetProfile();
  PetWorld? world;
  Simulator? get sim => world?.sim;
  PetBody get body => world!.body;
  MicSensor? mic;
  CameraSensor? cam;

  RigFrame? _f;
  Placement _p = const Placement(V2.zero, V2.zero, 0);
  Duration? _last;
  int _frameNo = 0;
  final Stopwatch _clock = Stopwatch()..start();

  // ---- 世界 ↔ 螢幕（dp）----
  double get s => profile.scale;
  double get floorY => m.height - m.navBar - 2;
  double get worldW => m.width / s;
  Offset toScreen(V2 w) => Offset(w.x * s, floorY - w.y * s);
  V2 toWorld(double x, double y) => V2(x / s, (floorY - y) / s);
  double get winW => CatBody.bodyLength * 2.6 * s;
  double get winH => CatBody.bodyLength * 1.5 * s + 6;
  // 貓頭（含耳朵）離身體中心約 0.8 體長：留一點邊，睡在邊邊也不會被切掉
  double get _minX => CatBody.bodyLength * 0.95;
  double get _maxX => worldW - CatBody.bodyLength * 0.95;
  double get _topY => (floorY - m.statusBar) / s - CatBody.bodyLength * 0.5;

  // ---- 視窗 ----
  _Win _win = _Win.small;
  Rect _winRect = Rect.zero; // 最後一次送出的位置（畫面內容依這個算）
  bool _blank = true; // 視窗大小切換中：先畫空白，避免舊畫面被拉伸
  Size? _expect;
  bool _transition = false;
  double _transT = 0;
  bool _resent = false;
  bool _placing = false;
  Rect? _queued;
  final Spring _winCx = Spring(0);
  double _settledT = 0;

  // ---- 觸控 ----
  _TouchMode _tm = _TouchMode.none;
  int _downMs = 0;
  double _moved = 0;
  bool _stroking = false;
  V2 _lastW = V2.zero;
  int _lastMoveMs = 0;
  double _strokeLogT = 0;
  bool _loggedStroke = false;

  // ---- 3D 實驗 ----
  Pet3D? _p3;
  bool _p3Loading = false;
  String? _p3Error;
  bool get _use3d => profile.look == 1 && _p3 != null;
  bool _sleepy = false;
  Offset _touchDp = Offset.zero;

  // ---- 效能紀錄（每 2 秒一次，也送回控制 App 顯示） ----
  final List<FrameTiming> _timings = [];
  double _perfT = 0;

  // ---- 觸覺、紀錄 ----
  bool _purrOn = false;
  bool _swatBuzzed = false;
  double _logT = 0;
  bool _paused = true;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    // 懸浮引擎在控制 App 開啟時就建立了，但視窗要等服務啟動才存在：收到 shown 才開始
    bridge.listen();
    _touchSub = bridge.touches.listen(_onTouch);
    _shownSub = bridge.shown.listen((v) => v ? _onShown() : _onHidden());
    _msgSub = FlutterOverlayWindow.overlayListener.listen(_onMessage);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  Future<void> _onShown() async {
    profile = await Store.load(reload: true);
    m = await bridge.metrics();
    var w = world;
    if (w == null) {
      w = PetWorld(
        traits: profile.traits,
        minX: _minX,
        maxX: _maxX,
        topY: _topY,
        startX: worldW * (0.3 + 0.4 * DateTime.now().millisecond / 1000),
      );
      world = w;
    } else {
      w.sim.traits = profile.traits;
      w.setBounds(_minX, _maxX, _topY);
    }
    petLog('overlay shown ${profile.name} size=${profile.size} $m');
    _winCx
      ..x = w.sim.loco.x * s
      ..v = 0;
    _paused = false;
    _last = null;
    _win = _Win.small;
    _beginTransition(body.mode == CarryMode.ground ? _smallRect() : _fullRect, body.mode == CarryMode.ground ? _Win.small : _Win.full);
    if (!_ticker.isActive) _ticker.start();
    if (mounted) setState(() {}); // 3D 畫面恢復自動更新
    _ensure3d();
    await _applySensors();
  }

  /// 第一次需要 3D 時才載入；這支手機不支援（Flutter GPU 沒開、驅動不行）就記下原因、退回 2D
  Future<void> _ensure3d() async {
    if (profile.look != 1 || _p3 != null || _p3Loading || _p3Error != null) return;
    _p3Loading = true;
    final sw = Stopwatch()..start();
    try {
      final p = await Pet3D.load();
      _p3 = p;
      petLog('3d ready in ${sw.elapsedMilliseconds} ms joints=${p.jointCount} clips=${p.clipNames.join(',')}');
    } catch (e) {
      _p3Error = '$e';
      petLog('3d unavailable: $e');
    } finally {
      _p3Loading = false;
    }
    if (mounted) setState(() {});
  }

  /// 視窗被收起（服務停止）：停動畫、麥克風、相機；貓的狀態留著，下次出現接著用
  void _onHidden() {
    if (_paused) return;
    _paused = true;
    _endTouch(sim, cancel: true);
    if (_purrOn) bridge.haptic('purr_off');
    _purrOn = false;
    if (_ticker.isActive) _ticker.stop();
    mic?.stop();
    cam?.stop();
    mic = null;
    cam = null;
    final st = sim?.stim;
    if (st != null) {
      st.micOn = false;
      st.cameraOn = false;
    }
    if (mounted) setState(() {}); // 3D 畫面停止自動更新
    petLog('overlay hidden');
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _ticker.dispose();
    _touchSub?.cancel();
    _shownSub?.cancel();
    _msgSub?.cancel();
    if (_purrOn) bridge.haptic('purr_off');
    mic?.stop();
    cam?.stop();
    super.dispose();
  }

  // ---------------- 控制 App 傳來的設定 ----------------
  void _onMessage(dynamic msg) {
    if (msg is! Map || msg['type'] != 'profile') return;
    final next = PetProfile.fromJson(Map<String, dynamic>.from(msg['data'] as Map));
    final oldS = s;
    final lookChanged = next.look != profile.look;
    profile = next;
    if (lookChanged) {
      petLog('look -> ${next.look == 1 ? '3d' : '2d'}');
      _ensure3d();
      setState(() {});
    }
    final w = world;
    if (w == null) return;
    w.sim.traits = next.traits;
    if (next.scale != oldS) {
      // 縮放：保持貓在螢幕上的位置不變
      w.shiftTo(w.sim.loco.x * oldS / next.scale);
      w.setBounds(_minX, _maxX, _topY);
      if (_win == _Win.small && !_transition) _beginTransition(_smallRect(), _Win.small);
    }
    petLog('profile updated traits=${next.traits.toJson()} scale=${next.scale}');
    _applySensors();
  }

  Future<void> _applySensors() async {
    final sm = sim;
    if (sm == null || _paused) return;
    if (profile.mic && mic == null) {
      final x = MicSensor(sm.stim);
      mic = x;
      if (!await x.start()) mic = null;
    } else if (!profile.mic && mic != null) {
      await mic!.stop();
      mic = null;
      sm.stim.micOn = false;
    }
    if (profile.camera && cam == null) {
      final x = CameraSensor(sm.stim);
      cam = x;
      if (!await x.start()) cam = null;
    } else if (!profile.camera && cam != null) {
      await cam!.stop();
      cam = null;
      sm.stim.cameraOn = false;
    }
  }

  // ---------------- 每一幀 ----------------
  void _tick(Duration elapsed) {
    final w = world;
    if (w == null) return;
    final sm = w.sim;
    final dt = _last == null ? 1 / 60 : clampD((elapsed - _last!).inMicroseconds / 1e6, 0, 0.05);
    _last = elapsed;
    _frameNo++;
    final now = _clock.elapsedMilliseconds;

    // 長按 → 抱起來
    if (_tm == _TouchMode.pet && !_stroking && now - _downMs > 450 && _f != null) {
      _tm = _TouchMode.grab;
      sm.stim.touchingPet = false;
      w.grab(_lastW);
      bridge.haptic('tick');
    }

    w.step(dt);
    final f = w.frame!, p = w.placement;
    _f = f;
    _p = p;
    if (body.landImpact > 120) bridge.haptic('tick');
    if (_use3d) _update3d(dt, sm, f, p);

    _updateWindow(dt, f, p);
    _haptics(sm);
    _log(dt, sm, f, p);
    _perfT += dt;
    if (_perfT >= 2) {
      _reportPerf(_perfT);
      _perfT = 0;
    }

    // 睡覺時每 4 幀才重畫一次（呼吸很慢），省電；3D 則把每秒幀數降到 20
    final quiet = sm.brain.asleep && _tm == _TouchMode.none && body.mode == CarryMode.ground && !_transition;
    if (quiet != _sleepy) setState(() => _sleepy = quiet);
    if (!quiet || _frameNo % 4 == 0) _repaint.value++;
  }

  // ---------------- 3D：把 2D 模擬的位置、方向、速度套到 3D 模型 ----------------
  void _update3d(double dt, Simulator sm, RigFrame f, Placement p) {
    final p3 = _p3!;
    p3.frame(screen: Size(m.width, m.height), floorY: floorY, s: s, window: _win == _Win.full ? _fullRect : _winRect);
    final place = vm.Matrix4.translationValues(p.pivotW.x, p.pivotW.y, 0)
        .multiplied(vm.Matrix4.rotationZ(p.angle))
        .multiplied(vm.Matrix4.translationValues(-p.pivotB.x, -p.pivotB.y, 0));
    final fx = sm.stim.fingerX;
    p3.update(
      dt,
      place: place,
      bodyX: (f.hip.x + f.shoulder.x) / 2,
      facing: f.facing,
      speed: sm.loco.vx.abs(),
      grounded: body.mode == CarryMode.ground,
      asleep: sm.brain.asleep,
      visible: !_blank,
      lookAt: fx == null ? null : vm.Vector3(fx, sm.stim.fingerY, 0),
    );
  }

  void _onTimings(List<FrameTiming> ts) {
    _timings.addAll(ts);
    if (_timings.length > 1000) _timings.removeRange(0, _timings.length - 1000);
  }

  Future<void> _reportPerf(double secs) async {
    final ts = List<FrameTiming>.of(_timings);
    _timings.clear();
    double q(List<double> v, double at) {
      if (v.isEmpty) return 0;
      v.sort();
      return v[((v.length - 1) * at).round()];
    }

    final uiMs = [for (final t in ts) t.buildDuration.inMicroseconds / 1000.0];
    final rsMs = [for (final t in ts) t.rasterDuration.inMicroseconds / 1000.0];
    final fps = ts.length / secs;
    final pw = await bridge.power();
    final look = _use3d ? '3d' : '2d';
    final r = {
      'type': 'perf',
      'look': look,
      'fps': fps,
      'ui50': q(uiMs, 0.5),
      'ui90': q(uiMs, 0.9),
      'rs50': q(rsMs, 0.5),
      'rs90': q(rsMs, 0.9),
      'mA': pw == null ? null : pw.currentUa / 1000.0,
      'level': pw?.level,
      'charging': pw?.charging,
      'sleepy': _sleepy,
      'err': _p3Error,
    };
    petLog('perf look=$look fps=${fps.toStringAsFixed(1)} '
        'ui50=${(r['ui50'] as double).toStringAsFixed(1)} ui90=${(r['ui90'] as double).toStringAsFixed(1)} '
        'rs50=${(r['rs50'] as double).toStringAsFixed(1)} rs90=${(r['rs90'] as double).toStringAsFixed(1)} ms '
        '${pw == null ? 'power=n/a' : 'cur=${(pw.currentUa / 1000).round()}mA lvl=${pw.level}% chg=${pw.charging}'} '
        'sleepy=$_sleepy win=${_win.name}');
    FlutterOverlayWindow.shareData(r).catchError((Object _) => false);
  }

  // ---------------- 視窗：平常小視窗跟著貓走，抱起／掉落時全螢幕 ----------------
  Rect _smallRect() {
    final cx = _winCx.x;
    return Rect.fromLTWH(cx - winW / 2, floorY + 6 - winH, winW, winH);
  }

  Rect get _fullRect => Rect.fromLTWH(0, 0, m.width, m.height);

  void _updateWindow(double dt, RigFrame f, Placement p) {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (_blank && _expect != null && view != null) {
      final sz = view.physicalSize / view.devicePixelRatio;
      if ((sz.width - _expect!.width).abs() < 1.5 && (sz.height - _expect!.height).abs() < 1.5) {
        _blank = false;
        _transition = false;
        petLog('window ${_win.name} ready ${sz.width.toStringAsFixed(0)}x${sz.height.toStringAsFixed(0)}');
      }
    }
    if (_transition) {
      // 保險：放置失敗或系統沒回應時，重送一次；再不行就直接顯示
      _transT += dt;
      if (_transT > 0.6 && !_resent && _expect != null) {
        _resent = true;
        bridge.place(_winRect.left, _winRect.top, _winRect.width, _winRect.height);
        petLog('window place resent');
      }
      if (_transT > 1.5) {
        _blank = false;
        _transition = false;
        petLog('window timeout: showing anyway');
      }
      return;
    }
    final wantFull = body.mode != CarryMode.ground || _tm == _TouchMode.grab || !body.settled;
    if (wantFull && _win == _Win.small) {
      _settledT = 0;
      _beginTransition(_fullRect, _Win.full);
      return;
    }
    // 視窗中心跟著貓的外框中心（平滑）
    final b = _use3d ? _p3!.screenBounds() : _bbox(f, p);
    final target = (b.left + b.right) / 2;
    if (_win == _Win.full) {
      _winCx.x = target;
      _winCx.v = 0;
      _settledT = wantFull ? 0 : _settledT + dt;
      if (_settledT > 0.3) _beginTransition(_smallRect(), _Win.small);
      return;
    }
    // 外框中心本身就是連續的，直接跟（用彈簧平滑會落後，跑起來頭會被視窗切掉）
    _winCx
      ..x = target
      ..v = 0;
    final r = _smallRect();
    final d = m.density;
    if ((r.left * d).round() != (_winRect.left * d).round() || (r.top * d).round() != (_winRect.top * d).round()) {
      _sendPlace(r);
    }
  }

  /// 貓在螢幕上的外框（dp）
  Rect _bbox(RigFrame f, Placement p) {
    var l = double.infinity, r = -double.infinity, t = double.infinity, bt = -double.infinity;
    void add(V2 b, double rad) {
      final o = toScreen(p.map(b));
      final rr = rad * s;
      l = math.min(l, o.dx - rr);
      r = math.max(r, o.dx + rr);
      t = math.min(t, o.dy - rr);
      bt = math.max(bt, o.dy + rr);
    }

    for (final q in f.tail) {
      add(q, f.tailW0);
    }
    add(f.head, f.headR * 1.8);
    add(f.hip, f.torsoT * 0.6);
    add(f.shoulder, f.torsoT * 0.6);
    for (final lg in f.legs) {
      add(lg.foot, 1);
    }
    return Rect.fromLTRB(l, t, r, bt);
  }

  void _beginTransition(Rect r, _Win target) {
    _transition = true;
    _transT = 0;
    _resent = false;
    _expect = null;
    _blank = true;
    _repaint.value++;
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      _win = target;
      _expect = r.size;
      _queued = null;
      _winRect = r;
      petLog('window -> ${target.name} ${r.left.toStringAsFixed(0)},${r.top.toStringAsFixed(0)} ${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)}');
      await bridge.place(r.left, r.top, r.width, r.height);
    });
  }

  void _sendPlace(Rect r) {
    if (_placing) {
      _queued = r;
      return;
    }
    _placing = true;
    _winRect = r;
    bridge.place(r.left, r.top, r.width, r.height).whenComplete(() {
      _placing = false;
      final q = _queued;
      _queued = null;
      if (q != null && _win == _Win.small && !_transition) _sendPlace(q);
    });
  }

  // ---------------- 觸控（螢幕座標，由原生端轉送） ----------------
  void _onTouch(RawTouch t) {
    final sm = sim, f = _f;
    if (sm == null || f == null) return;
    final w = toWorld(t.x, t.y);
    _touchDp = Offset(t.x, t.y);
    final now = _clock.elapsedMilliseconds;
    switch (t.action) {
      case RawTouch.down:
        _down(sm, f, w, now);
      case RawTouch.move:
        _move(sm, f, w, now);
      case RawTouch.up:
        _endTouch(sm);
      case RawTouch.cancel:
        _endTouch(sm, cancel: true);
    }
  }

  void _down(Simulator sm, RigFrame f, V2 w, int now) {
    if (body.mode == CarryMode.held) return;
    final region = _hit(f, w);
    _downMs = now;
    _lastMoveMs = now;
    _moved = 0;
    _stroking = false;
    _loggedStroke = false;
    _lastW = w;
    if (body.mode == CarryMode.air) {
      if (region != null) {
        _tm = _TouchMode.grab; // 半空中接住
        body.grab(w, f);
      }
      return;
    }
    if (region != null) {
      _tm = _TouchMode.pet;
      sm.stim.touchingPet = true;
    } else {
      _tm = _TouchMode.finger;
      sm.stim.fingerX = w.x;
      sm.stim.fingerY = math.max(0.0, w.y);
    }
    petLog('touch down mode=${_tm.name}${region == null ? '' : ' region=${region.name}'}');
  }

  void _move(Simulator sm, RigFrame f, V2 w, int now) {
    final dtS = math.max(1, now - _lastMoveMs) / 1000.0;
    final dist = w.dist(_lastW);
    _moved += dist * s; // dp
    switch (_tm) {
      case _TouchMode.grab:
        body.moveFinger(w);
      case _TouchMode.pet:
        if (!_stroking && _moved > 8) _stroking = true; // 約 Android 的 touch slop（8dp）
        if (_stroking) {
          final region = _hit(f, w);
          sm.stim.touchingPet = region != null;
          if (region != null && dist > 0.02) {
            sm.stim.strokeRegion = region;
            sm.stim.strokeSpeed = lerpD(sm.stim.strokeSpeed, dist / dtS, 0.3);
            sm.stim.sinceStroke = 0;
            _strokeLogT += dtS;
            if (!_loggedStroke || _strokeLogT > 0.5) {
              _loggedStroke = true;
              _strokeLogT = 0;
              petLog('touch stroke region=${region.name} speed=${sm.stim.strokeSpeed.toStringAsFixed(0)}');
            }
          }
        }
      case _TouchMode.finger:
        sm.stim.fingerX = w.x;
        sm.stim.fingerY = math.max(0.0, w.y);
        sm.stim.fingerSpeed = lerpD(sm.stim.fingerSpeed, (w.x - _lastW.x).abs() / dtS, 0.3);
      case _TouchMode.none:
        break;
    }
    _lastW = w;
    _lastMoveMs = now;
  }

  /// 摸到哪裡：3D 用骨頭投影到螢幕判斷，2D 用骨架的形狀
  BodyRegion? _hit(RigFrame f, V2 w) {
    final pad = math.max(1.3, 1.3 * 2.0 / s);
    final p3 = _p3;
    if (_use3d && p3 != null) return p3.hit(_touchDp, pad: pad);
    return hitPet(f, _p.unmap(w), pad: pad);
  }

  void _endTouch(Simulator? sm, {bool cancel = false}) {
    final now = _clock.elapsedMilliseconds;
    switch (_tm) {
      case _TouchMode.pet:
        if (!cancel && !_stroking && now - _downMs < 300 && sm != null) {
          sm.stim.poke = true;
          petLog('touch poke');
        }
      case _TouchMode.grab:
        body.release();
      case _TouchMode.finger:
        sm?.stim.fingerX = null;
        sm?.stim.fingerSpeed = 0;
      case _TouchMode.none:
        break;
    }
    sm?.stim.touchingPet = false;
    _tm = _TouchMode.none;
    _strokeLogT = 0;
  }

  // ---------------- 觸覺、紀錄 ----------------
  void _haptics(Simulator sm) {
    final want = sm.stim.touchingPet && sm.brain.intent.purr;
    if (want != _purrOn) {
      _purrOn = want;
      bridge.haptic(want ? 'purr_on' : 'purr_off');
      petLog(want ? 'purr haptic on' : 'purr haptic off');
    }
    final swat = sm.brain.act == Act.petted && sm.brain.phase == 9;
    if (swat && !_swatBuzzed) bridge.haptic('swat');
    _swatBuzzed = swat;
  }

  void _log(double dt, Simulator sm, RigFrame f, Placement p) {
    _logT += dt;
    if (_logT < 1) return;
    _logT = 0;
    final d = m.density;
    String px(V2 b) {
      final o = toScreen(p.map(b));
      return '${(o.dx * d).round()},${(o.dy * d).round()}';
    }

    final back = V2.lerp(f.hip, f.shoulder, 0.5) + V2(0, f.torsoT * 0.3);
    var backPx = px(back), headPx = px(f.head);
    final p3 = _p3;
    if (_use3d && p3 != null) {
      String sp(vm.Vector3 v) {
        final o = p3.camera.toScreen(v);
        return '${(o.dx * d).round()},${(o.dy * d).round()}';
      }

      backPx = sp(p3.backPoint);
      headPx = sp(p3.headCenter);
    }
    petLog('tick look=${_use3d ? '3d' : '2d'} act=${sm.brain.act.name} mode=${body.mode.name} win=${_win.name} '
        'x=${sm.loco.x.toStringAsFixed(1)} vx=${sm.loco.vx.toStringAsFixed(1)} back=$backPx head=$headPx '
        'fear=${sm.needs.fear.toStringAsFixed(2)} fatigue=${sm.needs.fatigue.toStringAsFixed(2)} (physical px)');
  }

  @override
  Widget build(BuildContext context) {
    final p3 = _p3;
    return SizedBox.expand(
      child: Stack(children: [
        if (p3 != null && profile.look == 1) Positioned.fill(child: p3.view(active: !_paused, maxFps: _sleepy ? 20 : null)),
        Positioned.fill(child: CustomPaint(painter: _OverlayPainter(this, _repaint))),
      ]),
    );
  }
}

/// 觸控判斷：摸到身體哪裡（身體座標）
BodyRegion? hitPet(RigFrame r, V2 p, {double pad = 1.3}) {
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

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.st, Listenable repaint) : super(repaint: repaint);
  final _OverlayPetState st;

  @override
  void paint(Canvas canvas, Size size) {
    final f = st._f;
    if (f == null || st._blank || st._use3d) return;
    final origin = st._win == _Win.full ? Offset.zero : st._winRect.topLeft;
    final s = st.s;
    final p = st._p;
    canvas.save();
    canvas.translate(-origin.dx, -origin.dy); // 之後都用螢幕座標（dp）
    final coat = coatAt(st.profile.coat);
    if (st.body.mode != CarryMode.ground) {
      // 懸空：影子在地板上，離越高越淡、越大
      final c = p.map(f.com);
      final h = math.max(0.0, c.y);
      final o = st.toScreen(V2(c.x, 0));
      canvas.drawOval(
        Rect.fromCenter(center: o, width: f.L * 1.1 * s * (1 + h / 120), height: math.max(2.0, f.L * 0.12 * s)),
        Paint()..color = Colors.black.withValues(alpha: 0.13 * math.exp(-h / 60)),
      );
    }
    final pw = st.toScreen(p.pivotW);
    canvas.translate(pw.dx, pw.dy);
    canvas.rotate(-p.angle);
    final view = WorldView(s: s, left: p.pivotB.x, floorY: p.pivotB.y * s);
    PetPainterKit.paint(canvas, view, f, coat, shadow: st.body.mode == CarryMode.ground);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => false;
}
