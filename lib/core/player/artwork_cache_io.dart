import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<Uri?> cacheArtwork(String trackId, Uint8List? bytes) async {
  if (bytes == null || bytes.isEmpty) return null;

  final cacheDirectory = await getTemporaryDirectory();
  final artworkDirectory = Directory(
    p.join(cacheDirectory.path, 'notification_artwork'),
  );
  if (!await artworkDirectory.exists()) {
    await artworkDirectory.create(recursive: true);
  }

  final safeId = trackId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final file = File(p.join(artworkDirectory.path, '$safeId.jpg'));
  if (!await file.exists() || await file.length() != bytes.length) {
    await file.writeAsBytes(bytes, flush: true);
  }
  return file.uri;
}
