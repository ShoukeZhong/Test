import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'overlay/overlay_pet.dart';
import 'ui/control_page.dart';

/// 控制 App：設定貓、權限、讓牠出現／收起來
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ControlApp());
}

/// 懸浮視窗用的第二個 Flutter 引擎從這裡開始（flutter_overlay_window 依名稱找這個函式）
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayPetApp());
}

class ControlApp extends StatelessWidget {
  const ControlApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Pet Overlay',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFFF2A65A), useMaterial3: true),
        home: const ControlPage(),
      );
}
