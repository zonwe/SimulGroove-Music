import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../database/app_database.dart';

Future<ja.AudioSource> createAudioSource(Track track, MediaItem item) async {
  return ja.AudioSource.uri(
    Uri.parse(item.extras!['uri']! as String),
    tag: item,
  );
}
