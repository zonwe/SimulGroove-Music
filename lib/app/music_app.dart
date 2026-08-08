import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_appearance.dart';
import '../features/shell/app_shell.dart';
import 'providers.dart';

class MusicApp extends ConsumerWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider).value;
    final seedColor = appearance?.seedColor ?? defaultThemeColor;
    return MaterialApp(
      title: 'Flutter Music',
      debugShowCheckedModeBanner: false,
      themeMode: appearance?.themeMode ?? ThemeMode.system,
      theme: _theme(Brightness.light, seedColor),
      darkTheme: _theme(Brightness.dark, seedColor),
      home: const AppShell(),
    );
  }
}

ThemeData _theme(Brightness brightness, Color seedColor) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );
  const controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );
  final windows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  return ThemeData(
    useMaterial3: true,
    splashFactory: NoSplash.splashFactory,
    highlightColor: scheme.primary.withValues(alpha: 0.12),
    hoverColor: scheme.primary.withValues(alpha: 0.08),
    focusColor: scheme.primary.withValues(alpha: 0.12),
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    // Keep Latin glyphs native to each platform and use a CJK family only as
    // fallback. Making YaHei the Windows primary also changes all Latin text.
    fontFamily: windows ? 'Segoe UI' : (android ? 'Roboto' : null),
    fontFamilyFallback: windows
        ? const ['Microsoft YaHei', 'Microsoft YaHei UI', 'Arial']
        : android
        ? const ['Noto Sans CJK SC', 'Noto Sans SC', 'sans-serif']
        : null,
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.secondaryContainer,
    ),
    drawerTheme: DrawerThemeData(backgroundColor: scheme.surfaceContainerLow),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: const FilledButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(controlShape)),
    ),
    outlinedButtonTheme: const OutlinedButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(controlShape)),
    ),
    textButtonTheme: const TextButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(controlShape)),
    ),
    segmentedButtonTheme: const SegmentedButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(controlShape)),
    ),
    chipTheme: ChipThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
    ),
  );
}
