import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../database/app_database.dart';

/// Builds a native local-file source for Windows tracks.
///
/// MPV external-file probing is disabled in the vendored media_kit adapter, so
/// the original local path can be passed through without hiding or copying it.
Future<ja.AudioSource> createAudioSource(Track track, MediaItem item) async {
  if (Platform.isWindows &&
      track.sourceType == 'windows_file' &&
      track.filePath != null) {
    return ja.AudioSource.uri(Uri.file(track.filePath!), tag: item);
  }
  return ja.AudioSource.uri(
    Uri.parse(item.extras!['uri']! as String),
    tag: item,
  );
}
