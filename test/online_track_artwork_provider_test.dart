import 'dart:typed_data';

import 'package:flutter_music/app/providers.dart';
import 'package:flutter_music/core/online_music/online_music_repository.dart';
import 'package:flutter_music/core/online_music/online_track.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failed artwork is not automatically retried', () async {
    final repository = _FailingArtworkRepository();
    final container = ProviderContainer(
      overrides: [onlineMusicRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    const track = OnlineTrack(
      provider: 'netease',
      trackId: 'track-1',
      title: 'Track',
      artists: ['Artist'],
      album: 'Album',
      playable: false,
      capabilities: {'artwork'},
      artworkUrl: '/api/online-music/tracks/netease/track-1/cover',
    );
    final provider = onlineTrackArtworkProvider(track);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    await expectLater(container.read(provider.future), throwsStateError);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(repository.artworkCalls, 1);
  });
}

class _FailingArtworkRepository implements OnlineMusicSearchRepository {
  var artworkCalls = 0;

  @override
  Future<Uint8List?> loadArtwork(OnlineTrack track) {
    artworkCalls++;
    throw StateError('Artwork unavailable');
  }

  @override
  Future<String?> loadLyrics(OnlineTrack track) => throw UnimplementedError();

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) =>
      throw UnimplementedError();

  @override
  Future<OnlineMusicSearchResult> search(String query, {String? cursor}) =>
      throw UnimplementedError();
}
