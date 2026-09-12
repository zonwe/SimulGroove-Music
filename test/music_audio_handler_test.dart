import 'dart:async';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/core/online_music/online_music_repository.dart';
import 'package:flutter_music/core/online_music/online_track.dart';
import 'package:flutter_music/core/online_music/online_track_playback.dart';
import 'package:flutter_music/core/player/music_audio_handler.dart';
import 'package:flutter_music/core/player/saved_playback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;

import 'support/fake_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeAudioPlayer player;
  late MusicAudioHandler handler;
  setUp(() {
    player = FakeAudioPlayer();
    handler = MusicAudioHandler(player: player);
  });
  tearDown(() => handler.disposePlayer());

  test('play command completes while playback remains active', () async {
    await handler.play().timeout(const Duration(seconds: 1));
    expect(player.playing, isTrue);
    expect(player.playback!.isCompleted, isFalse);
    expect(handler.playbackState.value.playing, isTrue);
  });

  test('late playback errors reach the shell error stream', () async {
    await handler.play();
    final error = handler.errors.first;
    player.playback!.completeError(StateError('simulated playback failure'));
    expect(await error, contains('播放失败'));
  });

  test('online playback starts before optional assets complete', () async {
    final repository = _Repository();
    final service = DefaultOnlineTrackPlayback(repository, handler);
    await service.play(_online).timeout(const Duration(seconds: 1));
    expect(player.playing, isTrue);
    expect(repository.lyrics.isCompleted, isFalse);
    final metadata = handler.mediaItem.firstWhere(
      (item) => item?.extras?['lyrics'] == 'lyrics',
    );
    repository.lyrics.complete('lyrics');
    expect((await metadata)?.id, 'online:test:track');
  });

  test(
    'late online metadata does not replace a newly selected local song',
    () async {
      final repository = _Repository();
      final service = DefaultOnlineTrackPlayback(repository, handler);
      await service.play(_online);
      await handler.playTracks([_local('local')]);
      repository.lyrics.complete('old lyrics');
      await Future<void>.delayed(Duration.zero);
      expect(handler.mediaItem.value?.id, 'local');
      expect(handler.mediaItem.value?.extras?['lyrics'], isNull);
    },
  );

  test(
    'restore retains shuffle order and position without starting audio',
    () async {
      final saved = SavedPlayback(
        baseIds: ['a', 'b'],
        queueIds: ['b', 'a'],
        currentId: 'b',
        position: const Duration(seconds: 25),
        repeatMode: AudioServiceRepeatMode.all,
        shuffle: true,
      );
      await handler.restoreLocalQueue(
        [_local('a'), _local('b')],
        saved,
        expectedRevision: 0,
      );
      expect(handler.queue.value.map((item) => item.id), ['b', 'a']);
      expect(handler.mediaItem.value?.id, 'b');
      expect(player.position, const Duration(seconds: 25));
      expect(player.loopMode, ja.LoopMode.all);
      expect(player.playCalls, 0);
      await handler.setShuffleMode(AudioServiceShuffleMode.none);
      expect(handler.queue.value.map((item) => item.id), ['a', 'b']);
      expect(handler.mediaItem.value?.id, 'b');
    },
  );

  test('restore cannot overwrite a user-selected queue', () async {
    await handler.playTracks([_local('new')]);
    final saved = SavedPlayback(
      baseIds: ['old'],
      queueIds: ['old'],
      currentId: 'old',
      position: Duration.zero,
      repeatMode: AudioServiceRepeatMode.none,
      shuffle: false,
    );
    await handler.restoreLocalQueue(
      [_local('old')],
      saved,
      expectedRevision: 0,
    );
    expect(handler.mediaItem.value?.id, 'new');
  });
}

Track _local(String id) => Track(
  id: id,
  sourceType: 'test',
  sourceId: id,
  uri: 'test://$id',
  title: id,
  artist: '',
  album: '',
  isAvailable: true,
  syncState: 'local',
  updatedAt: DateTime(2026),
);

const _online = OnlineTrack(
  provider: 'test',
  trackId: 'track',
  title: 'track',
  artists: [],
  album: '',
  playable: true,
  capabilities: {'playback', 'lyrics'},
);

class _Repository extends Fake implements OnlineMusicSearchRepository {
  final lyrics = Completer<String?>();
  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) async =>
      OnlinePlaybackSource(
        url: Uri.parse('https://example.test/audio'),
        expiresAt: DateTime(2099),
        headers: const {},
      );
  @override
  Future<String?> loadLyrics(OnlineTrack track) => lyrics.future;
  @override
  Future<Uint8List?> loadArtwork(OnlineTrack track) async => null;
}
