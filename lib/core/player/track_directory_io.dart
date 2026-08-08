import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> openTrackDirectory(String? filePath) async {
  if (filePath == null || filePath.isEmpty || !Platform.isWindows) return;
  final directory = p.dirname(filePath);
  await Process.run('explorer.exe', [directory]);
}
