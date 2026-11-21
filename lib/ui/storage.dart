import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../sim/profile.dart';

/// 使用者設定的貓（存在手機本機，不上傳）。控制 App 和懸浮視窗兩個 Flutter 引擎都讀這一份。
class PetProfile {
  PetProfile({
    this.name = '咪咪',
    this.coat = 0,
    this.personality = '',
    this.size = 1,
    this.mic = false,
    this.camera = false,
    this.look = 1,
  });

  String name;
  int coat;
  String personality;

  /// 0 小、1 中、2 大
  int size;
  bool mic;
  bool camera;

  /// 外觀：0 = 2D 手繪、1 = 3D（可行性實驗；手機不支援時自動退回 2D）
  int look;
  static const List<String> lookLabels = ['2D 手繪', '3D 實驗'];

  /// 每個世界單位在螢幕上幾 dp
  static const List<double> scales = [1.5, 2.0, 2.6];
  static const List<String> sizeLabels = ['小', '中', '大'];
  double get scale => scales[math.min(math.max(size, 0), scales.length - 1)];

  Traits get traits => compileTraits(personality).$1;

  Map<String, dynamic> toJson() => {
        'name': name,
        'coat': coat,
        'personality': personality,
        'size': size,
        'mic': mic,
        'camera': camera,
        'look': look,
      };

  factory PetProfile.fromJson(Map<String, dynamic> m) => PetProfile(
        name: m['name'] as String? ?? '咪咪',
        coat: (m['coat'] as num?)?.toInt() ?? 0,
        personality: m['personality'] as String? ?? '',
        size: (m['size'] as num?)?.toInt() ?? 1,
        mic: m['mic'] as bool? ?? false,
        camera: m['camera'] as bool? ?? false,
        look: (m['look'] as num?)?.toInt() ?? 1,
      );
}

class Store {
  static const _key = 'pet_profile_v3';

  /// [reload]：懸浮視窗是另一個引擎，要先 reload 才讀得到控制 App 剛存的值
  static Future<PetProfile> load({bool reload = false}) async {
    final p = await SharedPreferences.getInstance();
    if (reload) await p.reload();
    final raw = p.getString(_key);
    if (raw == null) return PetProfile();
    try {
      return PetProfile.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return PetProfile();
    }
  }

  static Future<void> save(PetProfile profile) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(profile.toJson()));
  }
}
