import 'package:flutter/material.dart';

const String themeModeSettingKey = 'appearance.theme_mode';
const String themeColorSettingKey = 'appearance.seed_color';
const Color defaultThemeColor = Color(0xFF536DFE);

class AppAppearance {
  const AppAppearance({required this.themeMode, required this.seedColor});

  factory AppAppearance.fromSettings(Map<String, String> settings) {
    final mode = switch (settings[themeModeSettingKey]) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final colorValue = int.tryParse(settings[themeColorSettingKey] ?? '');
    return AppAppearance(
      themeMode: mode,
      seedColor: colorValue == null ? defaultThemeColor : Color(colorValue),
    );
  }

  final ThemeMode themeMode;
  final Color seedColor;
}

String serializeThemeMode(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
  ThemeMode.system => 'system',
};
