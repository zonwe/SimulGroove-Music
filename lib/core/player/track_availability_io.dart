import 'dart:io';

import '../database/app_database.dart';

Future<String?> checkTrackAvailability(Track track) async {
  if (!track.isAvailable) return '歌曲已被标记为不可用';
  final path = track.filePath;
  if (path != null && path.isNotEmpty && !await File(path).exists()) {
    return '本地文件不存在：$path';
  }
  if (track.uri.startsWith('file://')) {
    final file = File.fromUri(Uri.parse(track.uri));
    if (!await file.exists()) return '本地文件不存在：${file.path}';
  }
  return null;
}
