import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowController {
  static final ValueNotifier<bool> compactMode = ValueNotifier(false);

  static bool get _isWindows => Platform.isWindows;

  static Future<void> initialize() async {
    if (!_isWindows) return;
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 720),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      title: 'Flutter Music',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setResizable(false);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  static Future<void> toggleCompact() async {
    if (!_isWindows) return;
    final next = !compactMode.value;
    compactMode.value = next;
    await windowManager.setAlwaysOnTop(next);
    await windowManager.setSize(
      next ? const Size(384, 144) : const Size(1280, 720),
      animate: true,
    );
    if (!next) await windowManager.center();
  }

  static Future<void> minimize() async {
    if (_isWindows) await windowManager.minimize();
  }

  static Future<void> close() async {
    if (_isWindows) await windowManager.close();
  }
}
