import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_music/core/theme/app_appearance.dart';

void main() {
  test('appearance defaults to system mode and persists selected values', () {
    final defaults = AppAppearance.fromSettings(const {});
    expect(defaults.themeMode, ThemeMode.system);
    expect(defaults.seedColor, defaultThemeColor);

    final selected = AppAppearance.fromSettings({
      themeModeSettingKey: 'dark',
      themeColorSettingKey: const Color(0xFF7E57C2).toARGB32().toString(),
    });
    expect(selected.themeMode, ThemeMode.dark);
    expect(selected.seedColor, const Color(0xFF7E57C2));
  });
}
