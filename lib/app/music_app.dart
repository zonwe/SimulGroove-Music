import 'package:flutter/material.dart';

import '../features/shell/app_shell.dart';

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF536DFE),
      brightness: Brightness.dark,
      surface: const Color(0xFF11131A),
    );
    return MaterialApp(
      title: 'Flutter Music',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFF0B0D12),
        cardTheme: const CardThemeData(
          color: Color(0xFF171A22),
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: const Color(0xFF101219),
          indicatorColor: colorScheme.primary.withValues(alpha: 0.2),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF171A22),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}
