import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sim/state.dart';
import 'sim/world.dart';
import 'ui/pet_world_page.dart';
import 'ui/setup_page.dart';
import 'ui/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const PetApp());
}

class PetApp extends StatelessWidget {
  const PetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pet Life',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFFD9712A), useMaterial3: true),
      home: const _Boot(),
    );
  }
}

class _Boot extends StatelessWidget {
  const _Boot();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(PetState, World)?>(
      future: Store.load(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final data = snap.data;
        if (data == null) return const SetupPage();
        return PetWorldPage(state: data.$1, world: data.$2);
      },
    );
  }
}
