import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowController {
  static final ValueNotifier<bool> compactMode = ValueNotifier(false);
  static final _trayListener = _TrayListener();
  static bool _isWindows = false;
  static bool _minimizeToTray = true;
  static bool _allowQuit = false;
  static Future<void> Function()? _onTogglePlay;
  static Future<void> Function()? _onPrevious;
  static Future<void> Function()? _onNext;
  static bool _trayReady = false;

  static bool get minimizeToTrayOnClose => _minimizeToTray;

  static Future<void> initialize({bool minimizeToTray = true}) async {
    _isWindows = Platform.isWindows;
    if (!_isWindows) return;
    _minimizeToTray = minimizeToTray;
    await windowManager.ensureInitialized();
    windowManager.addListener(_WindowListener());
    await windowManager.setPreventClose(_minimizeToTray);
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
    await _initializeTray();
  }

  static Future<void> setMinimizeToTray(bool value) async {
    _minimizeToTray = value;
    if (_isWindows) await windowManager.setPreventClose(value);
  }

  static void configureTrayActions({
    Future<void> Function()? onTogglePlay,
    Future<void> Function()? onPrevious,
    Future<void> Function()? onNext,
  }) {
    _onTogglePlay = onTogglePlay;
    _onPrevious = onPrevious;
    _onNext = onNext;
    if (_trayReady) _updateTrayMenu();
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
    if (!_isWindows) return;
    if (_minimizeToTray) {
      await windowManager.hide();
    } else {
      await quit();
    }
  }

  static Future<void> show() async {
    if (!_isWindows) return;
    await windowManager.show();
    await windowManager.focus();
  }

  static Future<void> quit() async {
    if (!_isWindows) return;
    _allowQuit = true;
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  static Future<void> _initializeTray() async {
    try {
      final data = await rootBundle.load(
        'windows/runner/resources/app_icon.ico',
      );
      final directory = await getTemporaryDirectory();
      final iconPath = p.join(directory.path, 'flutter_music_tray.ico');
      await File(iconPath).writeAsBytes(data.buffer.asUint8List());
      trayManager.addListener(_trayListener);
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('Flutter Music');
      _trayReady = true;
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show_window', label: '显示主窗口'),
            MenuItem.separator(),
            MenuItem(key: 'exit_app', label: '退出应用'),
          ],
        ),
      );
      await _updateTrayMenu();
    } catch (_) {
      // The app remains usable if a packaged build has no tray asset.
    }
  }

  static Future<void> _updateTrayMenu() => trayManager.setContextMenu(
    Menu(
      items: [
        MenuItem(key: 'show_window', label: '显示主窗口'),
        MenuItem.separator(),
        MenuItem(key: 'toggle_play', label: '播放 / 暂停'),
        MenuItem(key: 'previous', label: '上一首'),
        MenuItem(key: 'next', label: '下一首'),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: '退出应用'),
      ],
    ),
  );
}

class _WindowListener extends WindowListener {
  @override
  Future<void> onWindowClose() async {
    if (DesktopWindowController._allowQuit) return;
    await DesktopWindowController.close();
  }
}

class _TrayListener with TrayListener {
  @override
  void onTrayIconMouseDown() {
    DesktopWindowController.show();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      DesktopWindowController.show();
    } else if (menuItem.key == 'toggle_play') {
      DesktopWindowController._onTogglePlay?.call();
    } else if (menuItem.key == 'previous') {
      DesktopWindowController._onPrevious?.call();
    } else if (menuItem.key == 'next') {
      DesktopWindowController._onNext?.call();
    } else if (menuItem.key == 'exit_app') {
      DesktopWindowController.quit();
    }
  }
}
