import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/music_app.dart';
import 'app/providers.dart';
import 'core/database/app_database.dart';
import 'core/player/audio_backend.dart';
import 'core/player/music_audio_handler.dart';
import 'core/window/desktop_window_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureAudioBackend();
  await DesktopWindowController.initialize();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  final database = AppDatabase();
  final MusicAudioHandler audioHandler;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    audioHandler = MusicAudioHandler();
  } else {
    audioHandler = await AudioService.init<MusicAudioHandler>(
      builder: MusicAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'top.zonwe.music_player.playback',
        androidNotificationChannelName: '音乐播放',
        androidStopForegroundOnPause: false,
      ),
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const MusicApp(),
    ),
  );
}
