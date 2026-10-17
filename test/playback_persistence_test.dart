import 'package:audio_service/audio_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/core/player/music_audio_handler.dart';
import 'package:flutter_music/core/player/playback_persistence.dart';
import 'package:flutter_music/core/player/saved_playback.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local playback round-trips position and mode while online tickets are never saved',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.upsertTracks([_track('a'), _track('b')]);
      var player = FakeAudioPlayer();
      var handler = MusicAudioHandler(player: player);
      var persistence = PlaybackPersistence(db, handler);
      try {
        await persistence.initialize();
        await handler.playTracks(await db.allTracks(), initialIndex: 1);
        await handler.setRepeatMode(AudioServiceRepeatMode.one);
        await handler.seek(const Duration(seconds: 42));
        await persistence.saveNow();
        final stored = await db.readPlaybackSnapshot();
        expect(stored?.trackId, 'b');
        expect(stored?.positionMs, 42000);
        await persistence.dispose();
        await handler.disposePlayer();
        player = FakeAudioPlayer();
        handler = MusicAudioHandler(player: player);
        persistence = PlaybackPersistence(db, handler);
        await persistence.initialize();
        expect(handler.queue.value.map((item) => item.id), ['a', 'b']);
        expect(handler.mediaItem.value?.id, 'b');
        expect(player.position, const Duration(seconds: 42));
        expect(
          handler.playbackState.value.repeatMode,
          AudioServiceRepeatMode.one,
        );
        expect(player.playCalls, 0);
        await handler.playOnlineTrack(
          id: 'provider:song',
          title: 'online',
          artist: '',
          album: '',
          provider: 'provider',
          trackId: 'song',
          uri: Uri.parse('https://example.test/private-ticket'),
          headers: const {'Authorization': 'Bearer test-only'},
        );
        await persistence.saveNow();
        expect(await db.readPlaybackSnapshot(), isNull);
      } finally {
        await persistence.dispose();
        await handler.disposePlayer();
        await db.close();
      }
    },
  );

  test(
    'deleted current tracks fall back to another local queue item at zero',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final player = FakeAudioPlayer();
      final handler = MusicAudioHandler(player: player);
      final persistence = PlaybackPersistence(db, handler);
      try {
        await db.upsertTracks([_track('remaining')]);
        final snapshot = SavedPlayback(
          baseIds: ['removed', 'remaining'],
          queueIds: ['removed', 'remaining'],
          currentId: 'removed',
          position: const Duration(minutes: 1),
          repeatMode: AudioServiceRepeatMode.all,
          shuffle: false,
        );
        await db.savePlaybackSnapshot(
          PlaybackSnapshotsCompanion.insert(
            trackId: const Value('removed'),
            queueJson: Value(snapshot.queueJson),
            positionMs: const Value(60000),
            updatedAt: DateTime(2026),
          ),
        );
        await persistence.initialize();
        expect(handler.mediaItem.value?.id, 'remaining');
        expect(player.position, Duration.zero);
        expect(player.playing, isFalse);
      } finally {
        await persistence.dispose();
        await handler.disposePlayer();
        await db.close();
      }
    },
  );

  test('malformed and inconsistent saved queues are ignored', () {
    for (final json in [
      'broken',
      '[]',
      '{"version":1,"base":["a"],"queue":["b"]}',
      '{"version":1,"base":["a","a"],"queue":["a"]}',
    ]) {
      expect(
        SavedPlayback.decode(
          queueJson: json,
          currentId: 'a',
          positionMs: 0,
          repeatMode: 'none',
          shuffle: false,
        ),
        isNull,
      );
    }
  });
}

TracksCompanion _track(String id) => TracksCompanion.insert(
  id: id,
  sourceType: 'test',
  sourceId: id,
  uri: 'test://$id',
  title: id,
  durationMs: const Value(180000),
  updatedAt: DateTime(2026),
);
