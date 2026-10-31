import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/auth/auth_token_store.dart';
import '../core/auth/backend_gateway.dart';
import '../core/auth/http_backend_gateway.dart';
import '../core/database/app_database.dart';
import '../core/library/library_scanner.dart';
import '../core/library/library_scan_controller.dart';
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
import '../core/player/lyrics_settings.dart';
import '../core/player/music_audio_handler.dart';
import '../core/player/now_playing_layout.dart';

import '../core/theme/app_appearance.dart';
import '../core/update/update_service.dart';
import '../core/update/update_service_factory.dart';
import '../core/update/update_settings.dart';
import '../core/window/window_settings.dart';
import '../features/online_search/online_search_controller.dart';

export '../core/library/library_scan_controller.dart'
    show scanNotificationEnabledSettingKey;

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
final playbackErrorsProvider = StreamProvider<String>(
  (ref) => ref.watch(audioHandlerProvider).errors,
);
final libraryScanControllerProvider = Provider<LibraryScanController>((ref) {
  final controller = LibraryScanController(
    ref.watch(databaseProvider),
    ref.watch(scannerProvider),
    ref.watch(scanNotificationServiceProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
final backendGatewayProvider = Provider<BackendGateway>(
  // 每次请求从 AppSettings 解析服务器地址，账号页保存后立即生效。
  (ref) => HttpBackendGateway(
    readBaseUrl: () =>
        ref.read(databaseProvider).readSetting(backendBaseUrlSettingKey),
  ),
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
final authSessionBootstrapProvider = FutureProvider<BackendSession?>(
  (ref) => ref.watch(authRepositoryProvider).currentSession(),
);
final onlineMusicGatewayProvider = Provider<OnlineMusicGateway>(
  (ref) => HttpOnlineMusicGateway(
    readBaseUrl: () =>
        ref.read(databaseProvider).readSetting(backendBaseUrlSettingKey),
  ),
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

/// `AppSettings` 的单一订阅。
///
/// 设置页和播放器有十几处派生设置值；如果每个都自己 `watchSettings()`，
/// 一次写入就会产生同样数量的独立查询和流事件。这里只保留一条查询，
/// 其余派生 Provider 共享它的 `AsyncValue`。
final settingsProvider = StreamProvider<Map<String, String>>(
  (ref) => ref.watch(databaseProvider).watchSettings(),
);
final onlineSearchShowArtworkProvider = Provider<AsyncValue<bool>>(
  (ref) =>
      ref.watch(settingsProvider).whenData(onlineSearchShowArtworkFromSettings),
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
    saveDownloadedTrack: (track, {artwork}) =>
        ref.read(databaseProvider).upsertTracks([
          track,
        ], artworks: artwork == null ? null : {track.id.value: artwork}),
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

/// 单曲封面。
///
/// 封面拆到 `track_artworks` 之后，列表只查标量列；界面按可见行用这个 family
/// 单独取图，离开屏幕后自动释放，内存不再随音乐库规模增长。
final trackArtworkProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>(
      (ref, trackId) => ref.watch(databaseProvider).trackArtwork(trackId),
    );
final accountProvider = StreamProvider<Account?>(
  (ref) => ref.watch(databaseProvider).watchCurrentAccount(),
);

/// 当前生效的后端服务器地址（AppSettings 优先，编译期注入兜底），供账号页展示与编辑。
final backendBaseUrlProvider = Provider<AsyncValue<String>>(
  (ref) => ref
      .watch(settingsProvider)
      .whenData(
        (settings) => normalizeBackendBaseUrl(
          settings[backendBaseUrlSettingKey] ?? defaultBackendBaseUrl,
        ),
      ),
);
final playlistsProvider = StreamProvider<List<Playlist>>(
  (ref) => ref.watch(databaseProvider).watchPlaylists(),
);

/// 单个歌单的曲目流。
///
/// 页面里不要在 `build` 中直接 `ref.read(db).watchPlaylistTracks(...)`：
/// 每次重建都会新建一条流和一次查询，滚动或本地状态变化时会反复重订阅。
/// autoDispose 保证离开页面的歌单不再常驻订阅。
final playlistTracksProvider = StreamProvider.autoDispose
    .family<List<Track>, String>(
      (ref, playlistId) =>
          ref.watch(databaseProvider).watchPlaylistTracks(playlistId),
    );
final scanSourcesProvider = StreamProvider<List<ScanSource>>(
  (ref) => ref.watch(databaseProvider).watchScanSources(),
);
final onlineDownloadFilenameFormatProvider =
    Provider<AsyncValue<OnlineDownloadFilenameFormat>>(
      (ref) => ref
          .watch(settingsProvider)
          .whenData(
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
final appearanceProvider = Provider<AsyncValue<AppAppearance>>(
  (ref) => ref.watch(settingsProvider).whenData(AppAppearance.fromSettings),
);
final nowPlayingLayoutProvider = Provider<AsyncValue<NowPlayingLayout>>(
  (ref) => ref
      .watch(settingsProvider)
      .whenData(
        (settings) =>
            parseNowPlayingLayout(settings[nowPlayingLayoutSettingKey]),
      ),
);
final lyricsTapToSeekEnabledProvider = Provider<AsyncValue<bool>>(
  (ref) =>
      ref.watch(settingsProvider).whenData(lyricsTapToSeekEnabledFromSettings),
);
final lyricsTapToSeekConfirmProvider = Provider<AsyncValue<bool>>(
  (ref) =>
      ref.watch(settingsProvider).whenData(lyricsTapToSeekConfirmFromSettings),
);
final trayMinimizeOnCloseProvider = Provider<AsyncValue<bool>>(
  (ref) => ref
      .watch(settingsProvider)
      .whenData(
        (settings) => settings[trayMinimizeOnCloseSettingKey] != 'false',
      ),
);

/// 应用内更新：Windows 安装版使用静默安装；其他平台返回不支持。
final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  final service = createAppUpdateService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// 自动检查更新开关：启动时最多每 24 小时检查一次。
final updateAutoCheckProvider = Provider<AsyncValue<bool>>(
  (ref) => ref.watch(settingsProvider).whenData(updateAutoCheckFromSettings),
);

/// 自动下载更新开关：默认关闭，开启后才在后台下载新版本。
final updateAutoDownloadProvider = Provider<AsyncValue<bool>>(
  (ref) => ref.watch(settingsProvider).whenData(updateAutoDownloadFromSettings),
);

final scanNotificationEnabledProvider = Provider<AsyncValue<bool>>(
  (ref) => ref
      .watch(settingsProvider)
      .whenData(
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
