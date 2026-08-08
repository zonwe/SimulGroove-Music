import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/auth/auth_token_store.dart';
import '../core/auth/backend_gateway.dart';
import '../core/auth/http_backend_gateway.dart';
import '../core/database/app_database.dart';
import '../core/library/library_scanner.dart';
import '../core/library/scanner_factory.dart';
import '../core/player/music_audio_handler.dart';
import '../core/theme/app_appearance.dart';
import '../core/window/window_settings.dart';

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(),
);
final audioHandlerProvider = Provider<MusicAudioHandler>(
  (ref) => throw UnimplementedError(),
);
final scannerProvider = Provider<LibraryScanner>(
  (ref) => createLibraryScanner(),
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
final trayMinimizeOnCloseProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSettings()
      .map((settings) => settings[trayMinimizeOnCloseSettingKey] != 'false'),
);
