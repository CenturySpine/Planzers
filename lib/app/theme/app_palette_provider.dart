import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/brand_palette.dart';

final appPaletteProvider =
    AsyncNotifierProvider<AppPaletteNotifier, AppPaletteId>(
  AppPaletteNotifier.new,
);

class AppPaletteNotifier extends AsyncNotifier<AppPaletteId> {
  @override
  Future<AppPaletteId> build() async => AppPaletteId.oligarch;
}
