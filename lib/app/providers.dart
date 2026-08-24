import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/auth/auth_token_store.dart';
import '../core/auth/backend_gateway.dart';
import '../core/auth/http_backend_gateway.dart';
import '../core/database/app_database.dart';
import '../core/library/library_scanner.dart';
import '../core/library/scanner_factory.dart';
import '../core/notifications/scan_notification_service.dart';
import '../core/notifications/scan_notification_service_factory.dart';
import '../core/online_music/http_online_music_gateway.dart';
import '../core/online_music/online_download_platform.dart';
import '../core/online_music/online_download_platform_factory.dart';
import '../core/online_music/online_music_gateway.dart';
import '../core/online_music/online_music_repository.dart';
import '../core/online_music/online_search_settings.dart';
import '../core/online_music/online_track.dart';
import '../core/online_music/online_track_downloader.dart';
import '../core/online_music/online_track_playback.dart';
import '../core/player/equalizer_models.dart';
import '../core/player/music_audio_handler.dart';
import '../core/player/now_playing_layout.dart';

import '../core/theme/app_appearance.dart';
import '../core/window/window_settings.dart';
import '../features/online_search/online_search_controller.dart';

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(),
);
final audioHandlerProvider = Provider<MusicAudioHandler>(
  (ref) => throw UnimplementedError(),
);
final scannerProvider = Provider<LibraryScanner>(
  (ref) => createLibraryScanner(),
);
final scanNotificationServiceProvider = Provider<ScanNotificationService>(
  (ref) => createScanNotificationService(),
);
final backendGatewayProvider = Provider<BackendGateway>(
  (ref) => HttpBackendGateway(),
);
final authTokenStoreProvider = Provider<AuthTokenStore>(
  (ref) => SecureAuthTokenStore(),
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => BackendAuthRepository(
    ref.watch(databaseProvider),
    ref.watch(backendGatewayProvider),
    ref.watch(authTokenStoreProvider),
  ),
);
final onlineMusicGatewayProvider = Provider<OnlineMusicGateway>(
  (ref) => HttpOnlineMusicGateway(),
);
final onlineMusicRepositoryProvider = Provider<OnlineMusicSearchRepository>(
  (ref) => AuthenticatedOnlineMusicRepository(
    ref.watch(authRepositoryProvider),
    ref.watch(onlineMusicGatewayProvider),
  ),
);
final onlineSearchControllerProvider = Provider<OnlineSearchController>((ref) {
  final controller = OnlineSearchController(
    ref.watch(onlineMusicRepositoryProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
final onlineSearchShowArtworkProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSettings()
      .map(onlineSearchShowArtworkFromSettings),
);
final onlineTrackPlaybackProvider = Provider<OnlineTrackPlayback>(
  (ref) => DefaultOnlineTrackPlayback(
    ref.watch(onlineMusicRepositoryProvider),
    ref.watch(audioHandlerProvider),
  ),
);
final onlineDownloadPlatformProvider = Provider<OnlineDownloadPlatform>(
  (ref) => createOnlineDownloadPlatform(),
);
final onlineTrackDownloaderProvider = Provider<OnlineTrackDownloader>(
  (ref) => DefaultOnlineTrackDownloader(
    repository: ref.watch(onlineMusicRepositoryProvider),
    platform: ref.watch(onlineDownloadPlatformProvider),
    readSetting: (key) => ref.read(databaseProvider).readSetting(key),
    writeSetting: (key, value) =>
        ref.read(databaseProvider).setSetting(key, value),
    saveDownloadedTrack: (track) =>
        ref.read(databaseProvider).upsertTracks([track]),
  ),
);
final onlineTrackArtworkProvider = FutureProvider.autoDispose
    .family<Uint8List?, OnlineTrack>(
      (ref, track) {
        if (!track.capabilities.contains('artwork')) return null;
        return ref.watch(onlineMusicRepositoryProvider).loadArtwork(track);
      },
      // Artwork failures are already represented by a fallback in the UI.
      // Retrying every failed image ten times only amplifies upstream errors.
      retry: (_, _) => null,
    );
final tracksProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(databaseProvider).watchTracks(),
);
final accountProvider = StreamProvider<Account?>(
  (ref) => ref.watch(databaseProvider).watchCurrentAccount(),
);
final playlistsProvider = StreamProvider<List<Playlist>>(
  (ref) => ref.watch(databaseProvider).watchPlaylists(),
);
final scanSourcesProvider = StreamProvider<List<ScanSource>>(
  (ref) => ref.watch(databaseProvider).watchScanSources(),
);
final onlineDownloadFilenameFormatProvider =
    StreamProvider<OnlineDownloadFilenameFormat>(
      (ref) => ref
          .watch(databaseProvider)
          .watchSettings()
          .map(
            (settings) => parseOnlineDownloadFilenameFormat(
              settings[onlineDownloadFilenameFormatSettingKey],
            ),
          ),
    );
final likedTracksProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(databaseProvider).watchLikedTracks(),
);
final likedTrackIdsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(databaseProvider).watchLikedTrackIds(),
);
final appearanceProvider = StreamProvider<AppAppearance>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSettings()
      .map(AppAppearance.fromSettings),
);
final nowPlayingLayoutProvider = StreamProvider<NowPlayingLayout>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSettings()
      .map(
        (settings) =>
            parseNowPlayingLayout(settings[nowPlayingLayoutSettingKey]),
      ),
);
final trayMinimizeOnCloseProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSettings()
      .map((settings) => settings[trayMinimizeOnCloseSettingKey] != 'false'),
);
const scanNotificationEnabledSettingKey = 'library.scan_notification_enabled';

final scanNotificationEnabledProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSettings()
      .map(
        (settings) => settings[scanNotificationEnabledSettingKey] != 'false',
      ),
);

final customEqualizerPresetsProvider = StreamProvider<List<EqualizerPreset>>((
  ref,
) {
  return ref
      .watch(databaseProvider)
      .watchEqualizerPresets()
      .map(
        (rows) => rows
            .map(
              (row) => EqualizerPreset(
                id: row.id,
                name: row.name,
                gains: EqualizerPreset.parseGains(row.gainsJson),
                preampDb: row.preampDb,
                isCustom: true,
                remoteId: row.remoteId,
                updatedAt: row.updatedAt,
              ),
            )
            .toList(),
      );
});
