import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> openTrackDirectory(String? filePath) async {
  if (filePath == null || filePath.isEmpty) return;
  final directory = p.dirname(filePath);
  if (Platform.isWindows) {
    await Process.run('explorer.exe', [directory]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [directory]);
  }
}
