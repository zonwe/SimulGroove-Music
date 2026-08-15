import 'dart:async';

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
import 'core/shortcuts/desktop_shortcut_service.dart';
import 'core/startup/debug_artifact_cleanup.dart';
import 'core/window/desktop_window_controller.dart';
import 'core/window/window_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureAudioBackend();
  final database = AppDatabase();
  final traySetting = await database.readSetting(trayMinimizeOnCloseSettingKey);
  await DesktopWindowController.initialize(
    minimizeToTray: traySetting != 'false',
  );
  final MusicAudioHandler audioHandler;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    audioHandler = MusicAudioHandler();
  } else {
    audioHandler = await AudioService.init<MusicAudioHandler>(
      builder: MusicAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'top.comwe.simul_groove_player.playback',
        androidNotificationChannelName: '音乐播放',
        androidStopForegroundOnPause: false,
      ),
    );
  }
  DesktopWindowController.configureTrayActions(
    onTogglePlay: () async {
      if (audioHandler.playbackState.value.playing) {
        await audioHandler.pause();
      } else {
        await audioHandler.play();
      }
    },
    onPrevious: audioHandler.skipToPrevious,
    onNext: audioHandler.skipToNext,
  );
  await DesktopShortcutService.instance.initialize(
    database: database,
    handler: audioHandler,
  );

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const MusicApp(),
    ),
  );

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    unawaited(_configureAndroidAudioSession());
    unawaited(cleanupObsoleteDebugArtifacts());
  }
}

Future<void> _configureAndroidAudioSession() async {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
}
