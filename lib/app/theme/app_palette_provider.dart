import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/brand_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _palettePrefsKey = 'app_palette_id';

final appPaletteProvider =
    AsyncNotifierProvider<AppPaletteNotifier, AppPaletteId>(
  AppPaletteNotifier.new,
);

class AppPaletteNotifier extends AsyncNotifier<AppPaletteId> {
  @override
  Future<AppPaletteId> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_palettePrefsKey);
    final id = _parse(raw);
    if (raw != null && raw.isNotEmpty && raw != id.name) {
      await prefs.setString(_palettePrefsKey, id.name);
    }
    return id;
  }

  static AppPaletteId _parse(String? raw) {
    if (raw == null || raw.isEmpty) return AppPaletteId.oligarch;
    // Legacy prefs keys (before rename).
    if (raw == 'original') return AppPaletteId.cupidon;
    if (raw == 'lagune') return AppPaletteId.oligarch;
    for (final v in AppPaletteId.values) {
      if (v.name == raw) return v;
    }
    return AppPaletteId.oligarch;
  }

  Future<void> setPalette(AppPaletteId id) async {
    state = AsyncData(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_palettePrefsKey, id.name);
  }
}
