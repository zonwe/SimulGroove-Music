import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/database/app_database.dart';
import '../core/library/library_scanner.dart';
import '../core/library/scanner_factory.dart';
import '../core/player/music_audio_handler.dart';
import '../core/theme/app_appearance.dart';

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(),
);
final audioHandlerProvider = Provider<MusicAudioHandler>(
  (ref) => throw UnimplementedError(),
);
final scannerProvider = Provider<LibraryScanner>(
  (ref) => createLibraryScanner(),
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => MockAuthRepository(ref.watch(databaseProvider)),
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
