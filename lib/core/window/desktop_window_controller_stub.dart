import 'package:flutter/foundation.dart';

class DesktopWindowController {
  static final ValueNotifier<bool> compactMode = ValueNotifier(false);

  static Future<void> initialize() async {}
  static Future<void> toggleCompact() async {}
  static Future<void> minimize() async {}
  static Future<void> close() async {}
}
