import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../anim/pet_painter.dart';
import '../anim/rig.dart';
import '../sim/cat.dart';
import '../sim/motor.dart';
import '../sim/profile.dart';
import '../sim/util.dart';
import 'permissions.dart';
import 'storage.dart';

/// 控制 App：沒有寵物畫面，只負責設定和開關。寵物本身活在其他 App 上面的懸浮視窗裡。
class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> with WidgetsBindingObserver {
  PetProfile? _p;
  bool _active = false;
  bool _busy = false;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _persona = TextEditingController();
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveDebounce?.cancel();
    _name.dispose();
    _persona.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshActive();
  }

  Future<void> _load() async {
    final p = await Store.load();
    _name.text = p.name;
    _persona.text = p.personality;
    setState(() => _p = p);
    await _refreshActive();
  }

  Future<void> _refreshActive() async {
    final a = await FlutterOverlayWindow.isActive();
    if (mounted) setState(() => _active = a);
  }

  void _changed({bool restartIfActive = false}) {
    setState(() {});
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), () async {
      final p = _p!;
      await Store.save(p);
      if (_active) {
        if (restartIfActive) {
          // 麥克風／相機權限是在前景服務啟動時決定的：重開一次服務才會生效
          await FlutterOverlayWindow.closeOverlay();
          await Future<void>.delayed(const Duration(milliseconds: 400));
          await _showOverlay();
        } else {
          await FlutterOverlayWindow.shareData({'type': 'profile', 'data': p.toJson()});
        }
      }
    });
  }

  // ---------------- 顯示／收起 ----------------
  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_active) {
        await FlutterOverlayWindow.closeOverlay();
        petLog('overlay closed by user');
      } else {
        await _ensurePermissionsAndShow();
      }
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _refreshActive();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ensurePermissionsAndShow() async {
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要一個權限'),
          content: const Text('要讓貓出現在其他 App 上面，Android 需要你允許「顯示在其他應用程式上層」。\n\n'
              '等一下會打開設定頁，找到「Pet Overlay」把開關打開，再按返回就好。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('先不要')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('去開啟權限')),
          ],
        ),
      );
      if (go != true) return;
      await FlutterOverlayWindow.requestPermission();
      if (!await FlutterOverlayWindow.isPermissionGranted()) {
        _snack('還沒有開啟權限，貓沒辦法出現在其他 App 上面');
        return;
      }
    }
    // Android 13 起要允許通知，常駐通知才看得到（不允許也能運作）
    if (await Perms.sdk() >= 33 && !await Perms.granted(Perms.notifications)) {
      await Perms.request(Perms.notifications);
    }
    await _showOverlay();
  }

  Future<void> _showOverlay() async {
    final p = _p!;
    await Store.save(p);
    if (!mounted) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = CatBody.bodyLength * 2.35 * p.scale, h = CatBody.bodyLength * 1.5 * p.scale + 6;
    await FlutterOverlayWindow.showOverlay(
      width: (w * dpr).round(), // 這裡是實體像素（套件原始碼：showOverlay 不換算 dp）
      height: (h * dpr).round(),
      alignment: OverlayAlignment.topLeft,
      enableDrag: false, // 觸控全部交給貓自己處理
      flag: OverlayFlag.defaultFlag,
      positionGravity: PositionGravity.none,
      visibility: NotificationVisibility.visibilityPublic,
      overlayTitle: '${p.name}在你的螢幕上',
      overlayContent: '點這裡打開設定',
    );
    petLog('overlay shown');
  }

  // ---------------- 感官開關 ----------------
  Future<void> _toggleSense({required bool mic, required bool on}) async {
    final p = _p!;
    if (on) {
      final perm = mic ? Perms.mic : Perms.camera;
      if (!await Perms.granted(perm) && !await Perms.request(perm)) {
        _snack(mic ? '需要麥克風權限，貓才聽得到你' : '需要相機權限，貓才看得到你', settings: true);
        return;
      }
    }
    if (mic) {
      p.mic = on;
    } else {
      p.camera = on;
    }
    _changed(restartIfActive: true);
  }

  void _snack(String msg, {bool settings = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      action: settings ? SnackBarAction(label: '開設定', onPressed: Perms.openAppSettings) : null,
    ));
  }

  // ---------------- 畫面 ----------------
  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final (traits, words) = compileTraits(p.personality);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pet Overlay')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(height: 170, child: CatPreview(coat: p.coat)),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _toggle,
            icon: Icon(_active ? Icons.visibility_off : Icons.pets),
            label: Text(_active ? '收起來' : '讓牠出現在螢幕上'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 8),
          Text(
            _active
                ? '${p.name}正在螢幕底部走動。回到桌面或打開其他 App 都看得到牠。\n'
                    '摸牠：在身上滑動｜戳一下：輕點｜抱起來：長按後拖曳，放手牠會掉下來\n'
                    '在牠旁邊滑手指，牠會追'
                : '按下按鈕後，貓會出現在手機畫面最下面，蓋在其他 App 上面。',
            style: theme.textTheme.bodySmall,
          ),
          const Divider(height: 32),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '名字', border: OutlineInputBorder()),
            onChanged: (v) {
              p.name = v.trim().isEmpty ? '咪咪' : v.trim();
              _changed();
            },
          ),
          const SizedBox(height: 16),
          Text('毛色', style: theme.textTheme.titleSmall),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < catCoats.length; i++)
                ChoiceChip(
                  label: Text(catCoats[i].name),
                  selected: p.coat == i,
                  avatar: CircleAvatar(backgroundColor: catCoats[i].base),
                  onSelected: (_) {
                    p.coat = i;
                    _changed();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _persona,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '個性（用你的話描述）',
              hintText: '例：很黏人、有點膽小、超愛睡',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              p.personality = v;
              _changed();
            },
          ),
          const SizedBox(height: 6),
          Text(words.isEmpty ? '還沒認出關鍵字（使用預設個性）' : '認出：${words.join('、')}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          _bar('活潑', traits.activity),
          _bar('親人', traits.sociability),
          _bar('膽小', traits.fearfulness),
          _bar('衝動', traits.impulsiveness),
          const SizedBox(height: 16),
          Text('大小', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: [
              for (var i = 0; i < PetProfile.sizeLabels.length; i++) ButtonSegment(value: i, label: Text(PetProfile.sizeLabels[i])),
            ],
            selected: {p.size},
            onSelectionChanged: (v) {
              p.size = v.first;
              _changed();
            },
          ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('麥克風：聽得到你'),
            subtitle: const Text('拍手會嚇到牠；對牠說話，牠可能會過來'),
            value: p.mic,
            onChanged: (v) => _toggleSense(mic: true, on: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('前鏡頭：看得到你'),
            subtitle: const Text('在鏡頭前揮手，牠會盯著看；房間變暗，瞳孔會放大'),
            value: p.camera,
            onChanged: (v) => _toggleSense(mic: false, on: v),
          ),
          Text('聲音和影像只在手機上即時計算亮度、音量這類數字，不錄影、不錄音、不上傳。', style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Text('小米／紅米手機：還要在「應用設定 → 權限」打開「顯示懸浮視窗」和「後台彈出介面」。', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _bar(String label, double v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(width: 40, child: Text(label)),
          Expanded(child: LinearProgressIndicator(value: v, minHeight: 6, borderRadius: BorderRadius.circular(3))),
        ]),
      );
}

/// 設定頁上的即時預覽：同一套骨架與畫法，坐著看你
class CatPreview extends StatefulWidget {
  const CatPreview({super.key, required this.coat});
  final int coat;

  @override
  State<CatPreview> createState() => _CatPreviewState();
}

class _CatPreviewState extends State<CatPreview> with SingleTickerProviderStateMixin {
  final PetRig _rig = PetRig(50);
  final MotorIntent _it = MotorIntent();
  late final Ticker _ticker;
  final ValueNotifier<int> _tickN = ValueNotifier(0);
  RigFrame? _f;
  Duration? _last;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      final dt = _last == null ? 1 / 60 : clampD((e - _last!).inMicroseconds / 1e6, 0, 0.05);
      _last = e;
      _t += dt;
      _it
        ..reset()
        ..posture = Posture.sit
        ..lookAtViewer = 1
        ..tailUp = 0.35
        ..tailLash = 0.15;
      final cyc = _t % 5;
      if (cyc > 3.8 && cyc < 4.5) _it.eyes = 0.15; // 慢眨眼
      _f = _rig.update(dt, _it, 50, 0);
      _tickN.value++;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PreviewPainter(this, _tickN), size: Size.infinite);
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.st, Listenable r) : super(repaint: r);
  final _CatPreviewState st;

  @override
  void paint(Canvas canvas, Size size) {
    final f = st._f;
    if (f == null) return;
    final s = size.height * 0.78 / 32; // 坐姿連耳朵約 30 單位高
    final v = WorldView(s: s, left: 50 - size.width / (2 * s), floorY: size.height * 0.9);
    PetPainterKit.paint(canvas, v, f, coatAt(st.widget.coat));
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) => old.st.widget.coat != st.widget.coat;
}
