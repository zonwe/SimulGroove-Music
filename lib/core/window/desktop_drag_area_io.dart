import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

class DesktopDragArea extends StatelessWidget {
  const DesktopDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Platform.isWindows ? DragToMoveArea(child: child) : child;
}
