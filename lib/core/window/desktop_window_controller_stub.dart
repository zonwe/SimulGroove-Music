import 'package:flutter/foundation.dart';

class DesktopWindowController {
  static final ValueNotifier<bool> compactMode = ValueNotifier(false);
  static bool minimizeToTrayOnClose = true;

  static Future<void> initialize({bool minimizeToTray = true}) async {
    minimizeToTrayOnClose = minimizeToTray;
  }

  static Future<void> setMinimizeToTray(bool value) async {
    minimizeToTrayOnClose = value;
  }

  static Future<void> toggleCompact() async {}
  static Future<void> minimize() async {}
  static Future<void> close() async {}
  static Future<void> show() async {}
  static Future<void> quit() async {}
}
