import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/music_app.dart';
import 'app/providers.dart';
import 'core/database/app_database.dart';
import 'core/log/app_log.dart';
import 'core/notifications/scan_notification_service_factory.dart';
import 'core/player/audio_backend.dart';
import 'core/player/equalizer_models.dart';
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
      config: AudioServiceConfig(
        androidNotificationChannelId: 'top.zonwe.simul_groove_player.playback',
        androidNotificationChannelName: '音乐播放',
        androidNotificationChannelDescription: 'SimulGroove 音乐播放与媒体控制',
        androidNotificationIcon: 'drawable/ic_stat_music',
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
  final scanNotificationService = createScanNotificationService();
  await scanNotificationService.initialize();
  unawaited(_restoreEqualizerSettings(database, audioHandler));

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        audioHandlerProvider.overrideWithValue(audioHandler),
        scanNotificationServiceProvider.overrideWithValue(
          scanNotificationService,
        ),
      ],
      child: const MusicApp(),
    ),
  );

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    unawaited(_configureAndroidAudioSession(audioHandler));
    unawaited(cleanupObsoleteDebugArtifacts());
  }
}

Future<void> _restoreEqualizerSettings(
  AppDatabase database,
  MusicAudioHandler audioHandler,
) async {
  try {
    final settings = await database.watchSettings().first;
    final enabled = settings['audio.equalizer.enabled'] == 'true';
    final presetId = settings['audio.equalizer.preset'] ?? 'flat';
    final gainsJson = settings['audio.equalizer.gains'];
    final preampStr = settings['audio.equalizer.preamp'];

    var gains = EqualizerPreset.parseGains(gainsJson);
    var preamp = preampStr != null ? (double.tryParse(preampStr) ?? 0.0) : 0.0;
    if (gainsJson == null || gainsJson.isEmpty) {
      final defaultPreset = findDefaultEqualizerPreset(presetId);
      if (defaultPreset != null) {
        gains = List<double>.from(defaultPreset.gains);
        preamp = defaultPreset.preampDb;
      }
    }

    await audioHandler.applyEqualizer(
      enabled: enabled,
      gains: gains,
      preampDb: preamp,
      presetId: presetId,
    );
  } catch (error, stackTrace) {
    // 恢复均衡器是可选增强：平台音频效果不可用或设置损坏时按默认状态启动，
    // 不阻止应用启动，但需要留痕便于排查。
    AppLog.error('启动时恢复均衡器配置失败', error, stackTrace);
  }
}

Future<void> _configureAndroidAudioSession(
  MusicAudioHandler audioHandler,
) async {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  session.becomingNoisyEventStream.listen((_) {
    audioHandler.pause();
  });
}
