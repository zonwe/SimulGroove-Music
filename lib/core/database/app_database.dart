import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get username => text()();
  TextColumn get displayName => text()();
  TextColumn get avatarUri => text().nullable()();
  BoolColumn get isMock => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Tracks extends Table {
  TextColumn get id => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get accountId => text().nullable()();
  TextColumn get sourceType => text()();
  TextColumn get sourceId => text()();
  TextColumn get uri => text().unique()();
  TextColumn get filePath => text().nullable()();
  TextColumn get title => text()();
  TextColumn get artist => text().withDefault(const Constant('未知艺术家'))();
  TextColumn get album => text().withDefault(const Constant('未知专辑'))();
  IntColumn get durationMs => integer().nullable()();
  BlobColumn get artwork => blob().nullable()();
  TextColumn get lyrics => text().nullable()();
  IntColumn get fileSize => integer().nullable()();
  DateTimeColumn get modifiedAt => dateTime().nullable()();
  BoolColumn get isAvailable => boolean().withDefault(const Constant(true))();
  TextColumn get syncState => text().withDefault(const Constant('local'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ScanSources extends Table {
  TextColumn get id => text()();
  TextColumn get platform => text()();
  TextColumn get uri => text()();
  TextColumn get label => text()();
  DateTimeColumn get lastScannedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Playlists extends Table {
  TextColumn get id => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get accountId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get syncState => text().withDefault(const Constant('local'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PlaylistEntries extends Table {
  TextColumn get playlistId =>
      text().references(Playlists, #id, onDelete: KeyAction.cascade)();
  TextColumn get trackId =>
      text().references(Tracks, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {playlistId, trackId};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class PlaybackSnapshots extends Table {
  TextColumn get id => text().withDefault(const Constant('current'))();
  TextColumn get trackId => text().nullable()();
  TextColumn get queueJson => text().withDefault(const Constant('[]'))();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  TextColumn get repeatMode => text().withDefault(const Constant('none'))();
  BoolColumn get shuffle => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LikedTracks extends Table {
  TextColumn get trackId =>
      text().references(Tracks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {trackId};
}

@DriftDatabase(
  tables: [
    Accounts,
    Tracks,
    ScanSources,
    Playlists,
    PlaylistEntries,
    AppSettings,
    PlaybackSnapshots,
    LikedTracks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'flutter_music'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) => m.createAll(),
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) await m.createTable(likedTracks);
    },
  );

  Stream<List<Track>> watchTracks() =>
      (select(tracks)..orderBy([(row) => OrderingTerm.asc(row.title)])).watch();

  Future<List<Track>> allTracks() =>
      (select(tracks)..orderBy([(row) => OrderingTerm.asc(row.title)])).get();

  Future<Track?> findTrackByUri(String uri) =>
      (select(tracks)..where((row) => row.uri.equals(uri))).getSingleOrNull();

  Future<void> upsertTracks(Iterable<TracksCompanion> values) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(tracks, values.toList());
    });
  }

  Future<void> saveScanSource(ScanSourcesCompanion value) =>
      into(scanSources).insertOnConflictUpdate(value);

  Stream<List<ScanSource>> watchScanSources() => select(scanSources).watch();

  Stream<Map<String, String>> watchSettings() => select(
    appSettings,
  ).watch().map((rows) => {for (final row in rows) row.key: row.value});

  Future<void> setSetting(String key, String value) => into(
    appSettings,
  ).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));

  Stream<Account?> watchCurrentAccount() {
    final query = select(accounts)
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
      ..limit(1);
    return query.watchSingleOrNull();
  }

  Future<void> saveAccount(AccountsCompanion value) =>
      into(accounts).insertOnConflictUpdate(value);

  Future<void> clearAccounts() => delete(accounts).go();

  Future<String?> readSetting(String key) async {
    final row = await (select(
      appSettings,
    )..where((item) => item.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Stream<List<Playlist>> watchPlaylists() => (select(
    playlists,
  )..orderBy([(row) => OrderingTerm.asc(row.name)])).watch();

  Future<void> createPlaylist(PlaylistsCompanion value) =>
      into(playlists).insert(value);

  Future<void> updatePlaylistSync({
    required String id,
    required String remoteId,
    required String accountId,
  }) => (update(playlists)..where((row) => row.id.equals(id))).write(
    PlaylistsCompanion(
      remoteId: Value(remoteId),
      accountId: Value(accountId),
      syncState: const Value('synced'),
      updatedAt: Value(DateTime.now()),
    ),
  );

  Future<void> deletePlaylist(String id) =>
      (delete(playlists)..where((row) => row.id.equals(id))).go();

  Stream<List<Track>> watchPlaylistTracks(String playlistId) {
    final query =
        select(tracks).join([
            innerJoin(
              playlistEntries,
              playlistEntries.trackId.equalsExp(tracks.id),
            ),
          ])
          ..where(playlistEntries.playlistId.equals(playlistId))
          ..orderBy([OrderingTerm.asc(playlistEntries.position)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(tracks)).toList(),
    );
  }

  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    final existing = await (select(
      playlistEntries,
    )..where((row) => row.playlistId.equals(playlistId))).get();
    final nextPosition = existing.isEmpty
        ? 0
        : existing
                  .map((entry) => entry.position)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    await into(playlistEntries).insertOnConflictUpdate(
      PlaylistEntriesCompanion.insert(
        playlistId: playlistId,
        trackId: trackId,
        position: nextPosition,
        addedAt: DateTime.now(),
      ),
    );
    await (update(playlists)..where((row) => row.id.equals(playlistId))).write(
      PlaylistsCompanion(
        syncState: const Value('local'),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Stream<List<Track>> watchLikedTracks() {
    final query = select(tracks).join([
      innerJoin(likedTracks, likedTracks.trackId.equalsExp(tracks.id)),
    ])..orderBy([OrderingTerm.desc(likedTracks.addedAt)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(tracks)).toList(),
    );
  }

  Stream<Set<String>> watchLikedTrackIds() => select(
    likedTracks,
  ).watch().map((rows) => rows.map((row) => row.trackId).toSet());

  Future<void> setTrackLiked(String trackId, bool liked) async {
    if (liked) {
      await into(likedTracks).insertOnConflictUpdate(
        LikedTracksCompanion.insert(trackId: trackId, addedAt: DateTime.now()),
      );
    } else {
      await (delete(
        likedTracks,
      )..where((row) => row.trackId.equals(trackId))).go();
    }
  }
}
