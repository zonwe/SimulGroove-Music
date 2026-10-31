import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../library/scan_fingerprint.dart';

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
  TextColumn get lyrics => text().nullable()();
  IntColumn get fileSize => integer().nullable()();
  DateTimeColumn get modifiedAt => dateTime().nullable()();
  TextColumn get contentFingerprint => text().nullable()();
  BoolColumn get isAvailable => boolean().withDefault(const Constant(true))();
  TextColumn get syncState => text().withDefault(const Constant('local'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 曲目封面。
///
/// 封面是每首几百 KB 的 blob，放在 `Tracks` 里会让 `watchTracks()` 这样的全套
/// 列表查询把整个音乐库的封面都读进内存。拆表后列表只查标量列，界面按可见行
/// 单独取图；`onDelete: cascade` 保证删歌时封面一起消失。
class TrackArtworks extends Table {
  TextColumn get trackId =>
      text().references(Tracks, #id, onDelete: KeyAction.cascade)();
  BlobColumn get bytes => blob()();

  @override
  Set<Column<Object>> get primaryKey => {trackId};
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

@DataClassName('EqualizerPresetData')
class EqualizerPresets extends Table {
  TextColumn get id => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get accountId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get gainsJson => text()();
  RealColumn get preampDb => real().withDefault(const Constant(0.0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SyncTombstoneData')
class SyncTombstones extends Table {
  TextColumn get accountId => text()();
  TextColumn get entityType => text()();
  TextColumn get remoteKey => text()();
  DateTimeColumn get deletedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {accountId, entityType, remoteKey};
}

class LikedTrackSyncData {
  const LikedTrackSyncData(this.track, this.updatedAt);

  final Track track;
  final DateTime updatedAt;
}

const syncEntityPlaylist = 'playlist';
const syncEntityLikedTrack = 'likedTrack';
const syncEntityEqualizerPreset = 'equalizerPreset';

String _withTrailingSeparator(String value, String separator) =>
    value.endsWith(separator) ? value : '$value$separator';

Expression<bool> _startsWithLiteral(
  Expression<String> expression,
  String prefix,
) {
  const escapeCharacter = r'\';
  final escapedPrefix = prefix
      .replaceAll(escapeCharacter, '$escapeCharacter$escapeCharacter')
      .replaceAll('%', '$escapeCharacter%')
      .replaceAll('_', '${escapeCharacter}_');
  return expression.like('$escapedPrefix%', escapeChar: escapeCharacter);
}

@DriftDatabase(
  tables: [
    Accounts,
    Tracks,
    TrackArtworks,
    ScanSources,
    Playlists,
    PlaylistEntries,
    AppSettings,
    PlaybackSnapshots,
    LikedTracks,
    EqualizerPresets,
    SyncTombstones,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'flutter_music'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) => m.createAll(),
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) await m.createTable(likedTracks);
      if (from < 3) await m.createTable(equalizerPresets);
      if (from < 4) await m.createTable(syncTombstones);
      if (from < 5) await m.addColumn(tracks, tracks.contentFingerprint);
      if (from < 6) {
        // 先把 v5 的内嵌封面搬到独立表，再重建 tracks 丢掉这一列。
        // alterTable 会临时关闭外键，歌单/喜欢/封面表的引用不会级联丢失。
        await m.createTable(trackArtworks);
        await customStatement('''
          INSERT INTO track_artworks (track_id, bytes)
          SELECT id, artwork FROM tracks WHERE artwork IS NOT NULL
        ''');
        await m.alterTable(TableMigration(tracks));
      }
    },
    beforeOpen: (details) async {
      // Foreign-key declarations alone do not enable SQLite enforcement.
      // Repair rows left by older builds once, without touching valid links.
      const repairKey = 'database.foreign_key_repair_v1';
      await customStatement('PRAGMA foreign_keys = ON');
      if (await readSetting(repairKey) == null) {
        await transaction(() async {
          await customStatement('''
            DELETE FROM playlist_entries
            WHERE NOT EXISTS (
              SELECT 1 FROM playlists WHERE id = playlist_entries.playlist_id
            ) OR NOT EXISTS (
              SELECT 1 FROM tracks WHERE id = playlist_entries.track_id
            )
          ''');
          await customStatement('''
            DELETE FROM liked_tracks
            WHERE NOT EXISTS (
              SELECT 1 FROM tracks WHERE id = liked_tracks.track_id
            )
          ''');
          await setSetting(repairKey, 'done');
        });
      }
    },
  );

  Stream<List<Track>> watchTracks() =>
      (select(tracks)
            ..where((row) => row.sourceType.equals('online').not())
            ..orderBy([(row) => OrderingTerm.asc(row.title)]))
          .watch();

  Future<List<Track>> allTracks() =>
      (select(tracks)..orderBy([(row) => OrderingTerm.asc(row.title)])).get();

  Future<List<Track>> tracksForSync(String accountId) =>
      (select(tracks)
            ..where(
              (row) => row.accountId.isNull() | row.accountId.equals(accountId),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.title)]))
          .get();

  Future<Track?> findTrackByUri(String uri) =>
      (select(tracks)..where((row) => row.uri.equals(uri))).getSingleOrNull();

  Future<List<Track>> tracksByIds(Iterable<String> ids) async {
    final values = ids.toSet().toList(growable: false);
    final result = <Track>[];
    for (var start = 0; start < values.length; start += 500) {
      result.addAll(
        await (select(tracks)..where(
              (row) => row.id.isIn(
                values.sublist(start, (start + 500).clamp(0, values.length)),
              ),
            ))
            .get(),
      );
    }
    return result;
  }

  Future<PlaybackSnapshot?> readPlaybackSnapshot() => (select(
    playbackSnapshots,
  )..where((row) => row.id.equals('current'))).getSingleOrNull();

  Future<void> savePlaybackSnapshot(PlaybackSnapshotsCompanion value) =>
      into(playbackSnapshots).insertOnConflictUpdate(value);

  Future<void> clearPlaybackSnapshot() => delete(playbackSnapshots).go();

  /// 写入曲目，并可选地同时更新封面。
  ///
  /// [artworks] 里出现的 id 会覆盖封面（值为 null 表示清空）；没出现的曲目保持
  /// 原封面不动，方便「只补歌词」这类局部更新。
  Future<void> upsertTracks(
    Iterable<TracksCompanion> values, {
    Map<String, Uint8List?>? artworks,
  }) async {
    final rows = values.toList(growable: false);
    if (rows.isEmpty && (artworks == null || artworks.isEmpty)) return;
    await transaction(() async {
      if (rows.isNotEmpty) {
        await batch((batch) {
          batch.insertAllOnConflictUpdate(tracks, rows);
        });
      }
      if (artworks != null && artworks.isNotEmpty) {
        await _replaceTrackArtworks(artworks);
      }
    });
  }

  /// 覆盖指定曲目的封面行：先删后插，避免残留旧图。
  Future<void> _replaceTrackArtworks(Map<String, Uint8List?> artworks) async {
    final ids = artworks.keys.toList(growable: false);
    for (var start = 0; start < ids.length; start += 500) {
      final chunk = ids.sublist(start, (start + 500).clamp(0, ids.length));
      await (delete(
        trackArtworks,
      )..where((row) => row.trackId.isIn(chunk))).go();
    }
    final rows = [
      for (final entry in artworks.entries)
        if (entry.value case final Uint8List bytes)
          TrackArtworksCompanion.insert(trackId: entry.key, bytes: bytes),
    ];
    if (rows.isNotEmpty) {
      await batch(
        (batch) => batch.insertAllOnConflictUpdate(trackArtworks, rows),
      );
    }
  }

  /// 单曲封面。列表页按可见行单独取图，不再随曲目一起读整库封面。
  Future<Uint8List?> trackArtwork(String trackId) async {
    final row = await (select(
      trackArtworks,
    )..where((row) => row.trackId.equals(trackId))).getSingleOrNull();
    return row?.bytes;
  }

  /// 批量取封面（候选：播放队列快照恢复）。
  Future<Map<String, Uint8List>> trackArtworksFor(
    Iterable<String> trackIds,
  ) async {
    final ids = trackIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const {};
    final result = <String, Uint8List>{};
    for (var start = 0; start < ids.length; start += 500) {
      final chunk = ids.sublist(start, (start + 500).clamp(0, ids.length));
      final rows = await (select(
        trackArtworks,
      )..where((row) => row.trackId.isIn(chunk))).get();
      for (final row in rows) {
        result[row.trackId] = row.bytes;
      }
    }
    return result;
  }

  Future<void> saveScanSource(ScanSourcesCompanion value) =>
      into(scanSources).insertOnConflictUpdate(value);

  Stream<List<ScanSource>> watchScanSources() => select(scanSources).watch();

  Future<List<ScanFingerprint>> fingerprintsForScanSource(
    ScanSource source,
  ) async {
    final query = selectOnly(tracks)
      ..addColumns([
        tracks.filePath,
        tracks.fileSize,
        tracks.modifiedAt,
        tracks.contentFingerprint,
      ])
      ..where(_tracksFromScanSource(source));
    final rows = await query.get();
    return [
      for (final row in rows)
        if ((
              row.read(tracks.filePath),
              row.read(tracks.fileSize),
              row.read(tracks.modifiedAt),
              row.read(tracks.contentFingerprint),
            )
            case (
              final String path,
              final int size,
              final DateTime modified,
              final String fingerprint,
            ))
          ScanFingerprint(
            path: path,
            fileSize: size,
            modifiedAt: modified,
            fingerprint: fingerprint,
          ),
    ];
  }

  Future<void> replaceScanSourceTracks(
    ScanSource source,
    Iterable<TracksCompanion> values, {
    Map<String, Uint8List?>? artworks,
  }) async {
    final incoming = values.toList(growable: false);
    final incomingUris = incoming.map((value) => value.uri.value).toSet();
    await transaction(() async {
      // 逐块比较而不是生成一个巨大的 `uri NOT IN (...)`：一个来源可能有上万首
      // 曲目，SQLite 的绑定变量数量有上限（现代构建默认 32766），超限会直接抛错。
      final existingQuery = selectOnly(tracks)
        ..addColumns([tracks.id, tracks.uri])
        ..where(_tracksFromScanSource(source));
      final existing = await existingQuery.get();
      final staleIds = <String>[];
      for (final row in existing) {
        final id = row.read(tracks.id);
        if (id == null) continue;
        if (incomingUris.contains(row.read(tracks.uri))) continue;
        staleIds.add(id);
      }
      for (var start = 0; start < staleIds.length; start += 500) {
        final chunk = staleIds.sublist(
          start,
          (start + 500).clamp(0, staleIds.length),
        );
        await (delete(tracks)..where((row) => row.id.isIn(chunk))).go();
      }
      if (incoming.isNotEmpty) {
        await batch((batch) {
          batch.insertAllOnConflictUpdate(tracks, incoming);
        });
      }
      if (artworks != null && artworks.isNotEmpty) {
        await _replaceTrackArtworks(artworks);
      }
    });
  }

  Future<void> deleteScanSource(ScanSource source) async {
    await transaction(() async {
      final predicate = _tracksFromScanSource(source);
      await (delete(tracks)..where((row) => predicate)).go();
      await (delete(
        scanSources,
      )..where((row) => row.id.equals(source.id))).go();
    });
  }

  Expression<bool> _tracksFromScanSource(ScanSource source) {
    if (source.uri == 'media-store://external') {
      return tracks.sourceType.equals('android_media_store');
    }

    // Match descendants on a path-segment boundary. A raw `LIKE '$uri%'`
    // also matches sibling directories (for example Music and Music-old) and
    // treats % and _ in user-selected paths as pattern syntax.
    final windowsPrefix = _withTrailingSeparator(source.uri, r'\');
    final documentPrefix = _withTrailingSeparator(source.uri, '/');
    final windowsTracks =
        tracks.sourceType.equals('windows_file') &
        (tracks.sourceId.equals(source.uri) |
            _startsWithLiteral(tracks.sourceId, windowsPrefix));
    final linuxTracks =
        tracks.sourceType.equals('linux_file') &
        (tracks.sourceId.equals(source.uri) |
            _startsWithLiteral(tracks.sourceId, documentPrefix));
    final documentTracks =
        tracks.sourceType.equals('android_document_tree') &
        (tracks.sourceId.equals(source.uri) |
            _startsWithLiteral(tracks.sourceId, documentPrefix) |
            tracks.uri.equals(source.uri) |
            _startsWithLiteral(tracks.uri, documentPrefix));
    return windowsTracks | linuxTracks | documentTracks;
  }

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

  Future<void> replaceCurrentAccount(AccountsCompanion value) async {
    await transaction(() async {
      await delete(accounts).go();
      await into(accounts).insert(value);
    });
  }

  Future<void> clearAccounts() => delete(accounts).go();

  Future<Account?> _currentAccountOnce() {
    final query = select(accounts)
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
      ..limit(1);
    return query.getSingleOrNull();
  }

  Future<void> _recordSyncTombstone({
    required String accountId,
    required String entityType,
    required String remoteKey,
    DateTime? deletedAt,
  }) => into(syncTombstones).insertOnConflictUpdate(
    SyncTombstonesCompanion.insert(
      accountId: accountId,
      entityType: entityType,
      remoteKey: remoteKey,
      deletedAt: deletedAt ?? DateTime.now(),
    ),
  );

  Future<void> _removeSyncTombstone({
    required String accountId,
    required String entityType,
    required String remoteKey,
  }) =>
      (delete(syncTombstones)..where(
            (row) =>
                row.accountId.equals(accountId) &
                row.entityType.equals(entityType) &
                row.remoteKey.equals(remoteKey),
          ))
          .go();

  Future<List<SyncTombstoneData>> syncTombstonesForAccount(String accountId) =>
      (select(
        syncTombstones,
      )..where((row) => row.accountId.equals(accountId))).get();

  Future<void> replaceSyncTombstonesForAccount(
    String accountId,
    Iterable<SyncTombstonesCompanion> values,
  ) async {
    final rows = values.toList(growable: false);
    await transaction(() async {
      await (delete(
        syncTombstones,
      )..where((row) => row.accountId.equals(accountId))).go();
      if (rows.isNotEmpty) {
        await batch((batch) => batch.insertAll(syncTombstones, rows));
      }
    });
  }

  Future<String?> readSetting(String key) async {
    final row = await (select(
      appSettings,
    )..where((item) => item.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Stream<List<Playlist>> watchPlaylists() => (select(
    playlists,
  )..orderBy([(row) => OrderingTerm.asc(row.name)])).watch();

  Future<List<Playlist>> playlistsForSync(String accountId) =>
      (select(playlists)
            ..where(
              (row) => row.accountId.isNull() | row.accountId.equals(accountId),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .get();

  Future<void> createPlaylist(PlaylistsCompanion value) =>
      into(playlists).insert(value);

  Future<void> createPlaylistWithTracks(
    PlaylistsCompanion playlist,
    Iterable<TracksCompanion> trackValues,
  ) async {
    final values = trackValues.toList(growable: false);
    await transaction(() async {
      await into(playlists).insert(playlist);
      for (final value in values) {
        // A downloaded local copy wins over an online placeholder with the
        // same stable id, so adding it to another playlist never makes it
        // remote-only again.
        await into(tracks).insert(value, mode: InsertMode.insertOrIgnore);
      }
      for (var index = 0; index < values.length; index++) {
        await into(playlistEntries).insert(
          PlaylistEntriesCompanion.insert(
            playlistId: playlist.id.value,
            trackId: values[index].id.value,
            position: index,
            addedAt: DateTime.now(),
          ),
        );
      }
    });
  }

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

  Future<void> deletePlaylist(String id) async {
    await transaction(() async {
      final playlist = await (select(
        playlists,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (playlist != null) {
        final accountId =
            playlist.accountId ?? (await _currentAccountOnce())?.id;
        if (accountId != null) {
          await _recordSyncTombstone(
            accountId: accountId,
            entityType: syncEntityPlaylist,
            remoteKey: playlist.remoteId ?? 'playlist-${playlist.id}',
          );
        }
      }
      await deletePlaylistFromSync(id);
    });
  }

  Future<void> deletePlaylistFromSync(String id) =>
      (delete(playlists)..where((row) => row.id.equals(id))).go();

  Future<void> savePlaylistFromSync({
    required String id,
    required String remoteId,
    required String accountId,
    required String name,
    required DateTime createdAt,
    required DateTime updatedAt,
    required Iterable<String> trackIds,
    Iterable<TracksCompanion> missingTracks = const [],
  }) async {
    final ids = trackIds.toList(growable: false);
    final tracksToInsert = missingTracks.toList(growable: false);
    await transaction(() async {
      await into(playlists).insertOnConflictUpdate(
        PlaylistsCompanion.insert(
          id: id,
          remoteId: Value(remoteId),
          accountId: Value(accountId),
          name: name,
          syncState: const Value('synced'),
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      );
      for (final track in tracksToInsert) {
        await into(tracks).insert(track, mode: InsertMode.insertOrIgnore);
      }
      await (delete(
        playlistEntries,
      )..where((row) => row.playlistId.equals(id))).go();
      for (var index = 0; index < ids.length; index++) {
        await into(playlistEntries).insert(
          PlaylistEntriesCompanion.insert(
            playlistId: id,
            trackId: ids[index],
            position: index,
            addedAt: updatedAt,
          ),
        );
      }
    });
  }

  Future<void> deleteUnreferencedSyncedTrackPlaceholders() async {
    // `NOT IN (大量 id)` 会随歌单/喜欢规模一起增长，并有变量数量上限；
    // 相关子查询表达「没有任何引用」既不占内存也避免拼接超长参数列表。
    await customStatement('''
      DELETE FROM tracks
      WHERE source_type = 'synced'
        AND NOT EXISTS (
          SELECT 1 FROM playlist_entries
          WHERE playlist_entries.track_id = tracks.id
        )
        AND NOT EXISTS (
          SELECT 1 FROM liked_tracks
          WHERE liked_tracks.track_id = tracks.id
        )
    ''');
  }

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

  /// 一次性读取歌单曲目。
  ///
  /// 同步等只需要当前值的场景不要用 `watchPlaylistTracks(...).first`：那会为每个
  /// 歌单建立并立即取消一条流订阅，歌单多时就是 N 次额外查询。
  Future<List<Track>> playlistTracks(String playlistId) async {
    final query =
        select(tracks).join([
            innerJoin(
              playlistEntries,
              playlistEntries.trackId.equalsExp(tracks.id),
            ),
          ])
          ..where(playlistEntries.playlistId.equals(playlistId))
          ..orderBy([OrderingTerm.asc(playlistEntries.position)]);
    final rows = await query.get();
    return rows.map((row) => row.readTable(tracks)).toList();
  }

  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    await transaction(() async {
      final maximumPosition = playlistEntries.position.max();
      final positionQuery = selectOnly(playlistEntries)
        ..addColumns([maximumPosition])
        ..where(playlistEntries.playlistId.equals(playlistId));
      final currentMaximum = await positionQuery
          .map((row) => row.read(maximumPosition))
          .getSingle();
      await into(playlistEntries).insertOnConflictUpdate(
        PlaylistEntriesCompanion.insert(
          playlistId: playlistId,
          trackId: trackId,
          position: (currentMaximum ?? -1) + 1,
          addedAt: DateTime.now(),
        ),
      );
      await _markPlaylistLocal(playlistId);
    });
  }

  /// 批量把已在库中的曲目加入歌单。
  ///
  /// 与逐条调用 [addTrackToPlaylist] 相比，整批共用一个事务和一次歌单
  /// 时间戳更新，页面层多选加入歌单时避免 N+1 写入。
  Future<void> addExistingTracksToPlaylist(
    String playlistId,
    Iterable<String> trackIds,
  ) async {
    final ids = trackIds.toSet().toList(growable: false);
    if (ids.isEmpty) return;
    await transaction(() async {
      final maximumPosition = playlistEntries.position.max();
      final positionQuery = selectOnly(playlistEntries)
        ..addColumns([maximumPosition])
        ..where(playlistEntries.playlistId.equals(playlistId));
      var position =
          (await positionQuery
                  .map((row) => row.read(maximumPosition))
                  .getSingle() ??
              -1) +
          1;
      final addedAt = DateTime.now();
      await batch((batch) {
        // 注意：不能用 batch.replaceAll——它只 UPDATE 已存在的行，
        // 不会插入不存在的歌单条目；insertAllOnConflictUpdate 与
        // addTrackToPlaylist 的 upsert（存在则移到末尾）语义一致。
        batch.insertAllOnConflictUpdate(playlistEntries, [
          for (final id in ids)
            PlaylistEntriesCompanion.insert(
              playlistId: playlistId,
              trackId: id,
              position: position++,
              addedAt: addedAt,
            ),
        ]);
      });
      await _markPlaylistLocal(playlistId);
    });
  }

  Future<void> addTracksToPlaylist(
    String playlistId,
    Iterable<TracksCompanion> trackValues,
  ) async {
    final values = trackValues.toList(growable: false);
    if (values.isEmpty) return;
    await transaction(() async {
      for (final value in values) {
        await into(tracks).insert(value, mode: InsertMode.insertOrIgnore);
      }
      final maximumPosition = playlistEntries.position.max();
      final positionQuery = selectOnly(playlistEntries)
        ..addColumns([maximumPosition])
        ..where(playlistEntries.playlistId.equals(playlistId));
      var position =
          (await positionQuery
                  .map((row) => row.read(maximumPosition))
                  .getSingle() ??
              -1) +
          1;
      for (final value in values) {
        await into(playlistEntries).insertOnConflictUpdate(
          PlaylistEntriesCompanion.insert(
            playlistId: playlistId,
            trackId: value.id.value,
            position: position++,
            addedAt: DateTime.now(),
          ),
        );
      }
      await _markPlaylistLocal(playlistId);
    });
  }

  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {
    await transaction(() async {
      await (delete(playlistEntries)..where(
            (row) =>
                row.playlistId.equals(playlistId) & row.trackId.equals(trackId),
          ))
          .go();
      await _markPlaylistLocal(playlistId);
    });
  }

  Future<void> _markPlaylistLocal(String playlistId) =>
      (update(playlists)..where((row) => row.id.equals(playlistId))).write(
        PlaylistsCompanion(
          syncState: const Value('local'),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Stream<List<Track>> watchLikedTracks() {
    final query = select(tracks).join([
      innerJoin(likedTracks, likedTracks.trackId.equalsExp(tracks.id)),
    ])..orderBy([OrderingTerm.desc(likedTracks.addedAt)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(tracks)).toList(),
    );
  }

  Future<List<LikedTrackSyncData>> allLikedTracksForSync({
    String? accountId,
  }) async {
    final query = select(
      tracks,
    ).join([innerJoin(likedTracks, likedTracks.trackId.equalsExp(tracks.id))]);
    if (accountId != null) {
      query.where(
        tracks.accountId.isNull() | tracks.accountId.equals(accountId),
      );
    }
    final rows = await query.get();
    return rows
        .map(
          (row) => LikedTrackSyncData(
            row.readTable(tracks),
            row.readTable(likedTracks).addedAt,
          ),
        )
        .toList(growable: false);
  }

  Stream<Set<String>> watchLikedTrackIds() => select(
    likedTracks,
  ).watch().map((rows) => rows.map((row) => row.trackId).toSet());

  Future<void> setTrackLiked(String trackId, bool liked) async {
    await transaction(() async {
      final track = await (select(
        tracks,
      )..where((row) => row.id.equals(trackId))).getSingleOrNull();
      final account = await _currentAccountOnce();
      if (liked) {
        if (track != null && account != null) {
          await _removeSyncTombstone(
            accountId: account.id,
            entityType: syncEntityLikedTrack,
            remoteKey: track.uri,
          );
        }
        await setTrackLikedFromSync(trackId, true, updatedAt: DateTime.now());
      } else {
        if (track != null && account != null) {
          await _recordSyncTombstone(
            accountId: account.id,
            entityType: syncEntityLikedTrack,
            remoteKey: track.uri,
          );
        }
        await setTrackLikedFromSync(trackId, false);
      }
    });
  }

  Future<void> setTrackLikedFromSync(
    String trackId,
    bool liked, {
    DateTime? updatedAt,
  }) async {
    if (liked) {
      await into(likedTracks).insertOnConflictUpdate(
        LikedTracksCompanion.insert(
          trackId: trackId,
          addedAt: updatedAt ?? DateTime.now(),
        ),
      );
      return;
    }
    await (delete(
      likedTracks,
    )..where((row) => row.trackId.equals(trackId))).go();
  }

  Stream<List<EqualizerPresetData>> watchEqualizerPresets() => (select(
    equalizerPresets,
  )..orderBy([(row) => OrderingTerm.asc(row.name)])).watch();

  Future<List<EqualizerPresetData>> allEqualizerPresets() => (select(
    equalizerPresets,
  )..orderBy([(row) => OrderingTerm.asc(row.name)])).get();

  Future<List<EqualizerPresetData>> equalizerPresetsForSync(String accountId) =>
      (select(equalizerPresets)
            ..where(
              (row) => row.accountId.isNull() | row.accountId.equals(accountId),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .get();

  Future<void> saveEqualizerPreset(EqualizerPresetsCompanion value) =>
      into(equalizerPresets).insertOnConflictUpdate(value);

  Future<void> deleteEqualizerPreset(String id) async {
    await transaction(() async {
      final preset = await (select(
        equalizerPresets,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (preset != null) {
        final accountId = preset.accountId ?? (await _currentAccountOnce())?.id;
        if (accountId != null) {
          await _recordSyncTombstone(
            accountId: accountId,
            entityType: syncEntityEqualizerPreset,
            remoteKey: preset.remoteId ?? 'preset-${preset.id}',
          );
        }
      }
      await deleteEqualizerPresetFromSync(id);
    });
  }

  Future<void> deleteEqualizerPresetFromSync(String id) =>
      (delete(equalizerPresets)..where((row) => row.id.equals(id))).go();
}
