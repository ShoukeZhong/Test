import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../sim/state.dart';
import '../sim/world.dart';

/// 存在手機本機（不上傳）
class Store {
  static const _key = 'pet_life_v2';

  static Future<(PetState, World)?> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final s = PetState.fromJson(Map<String, dynamic>.from(m['pet'] as Map));
      final w = World()..loadJson(Map<String, dynamic>.from(m['world'] as Map));
      return (s, w);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(PetState s, World w) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode({'pet': s.toJson(), 'world': w.toJson()}));
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
