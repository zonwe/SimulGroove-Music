import 'dart:io';

import 'package:just_audio_media_kit/just_audio_media_kit.dart';

Future<void> configureAudioBackend() async {
  if (Platform.isWindows || Platform.isLinux) {
    JustAudioMediaKit.ensureInitialized();
  }
}
