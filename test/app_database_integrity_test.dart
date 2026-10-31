import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'foreign keys cascade deleted tracks and playlists without affecting peers',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _seed(db);
      expect(
        (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
          'foreign_keys',
        ),
        1,
      );
      await db.deletePlaylist('first');
      expect(
        (await db.select(db.playlistEntries).get()).single.playlistId,
        'second',
      );
      expect(await db.select(db.likedTracks).get(), hasLength(1));
      expect(await db.trackArtwork('track'), isNotNull);
      await (db.delete(db.tracks)..where((row) => row.id.equals('track'))).go();
      expect(await db.select(db.playlistEntries).get(), isEmpty);
      expect(await db.select(db.likedTracks).get(), isEmpty);
      expect(await db.trackArtwork('track'), isNull);
      expect(await db.watchPlaylists().first, hasLength(1));
      await expectLater(
        db.addTrackToPlaylist('second', 'missing'),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('opening a legacy database removes only orphan relationships', () async {
    final dir = await Directory.systemTemp.createTemp('music_fk_repair_');
    final file = File('${dir.path}/test.db');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    try {
      await _seed(db);
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db.customStatement(
        "DELETE FROM app_settings WHERE key = 'database.foreign_key_repair_v1'",
      );
      await db.customStatement(
        "INSERT INTO playlist_entries VALUES ('missing', 'track', 0, 0), ('first', 'missing', 0, 0)",
      );
      await db.customStatement(
        "INSERT INTO liked_tracks VALUES ('missing', 0)",
      );
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      expect(await db.select(db.playlistEntries).get(), hasLength(2));
      expect((await db.select(db.likedTracks).get()).single.trackId, 'track');
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      expect(await db.allTracks(), hasLength(1));
      expect(await db.watchPlaylists().first, hasLength(2));
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}

Future<void> _seed(AppDatabase db) async {
  final now = DateTime(2026);
  await db.upsertTracks(
    [
      TracksCompanion.insert(
        id: 'track',
        sourceType: 'test',
        sourceId: 'track',
        uri: 'test://track',
        title: 'track',
        updatedAt: now,
      ),
    ],
    artworks: {
      'track': Uint8List.fromList([0x0A, 0x0B]),
    },
  );
  for (final id in ['first', 'second']) {
    await db.createPlaylist(
      PlaylistsCompanion.insert(
        id: id,
        name: id,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.addTrackToPlaylist(id, 'track');
  }
  await db.setTrackLiked('track', true);
}
