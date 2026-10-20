import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_music/app/providers.dart';
import 'package:flutter_music/core/online_music/online_music_repository.dart';
import 'package:flutter_music/core/online_music/online_track.dart';
import 'package:flutter_music/core/online_music/online_track_playback.dart';
import 'package:flutter_music/features/online_search/online_collection_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('在线歌手页滚动到底部会继续加载后续页', (tester) async {
    tester.view.physicalSize = const Size(375, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _PagedArtistRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineMusicRepositoryProvider.overrideWithValue(repository),
          onlineTrackPlaybackProvider.overrideWithValue(_FakePlayback()),
          onlineSearchShowArtworkProvider.overrideWithValue(
            const AsyncData(false),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: OnlineCollectionPage(
              request: const OnlineCollectionRequest(
                kind: OnlineCollectionKind.artist,
                value: 'Artist B',
                seedTracks: [],
              ),
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Artist Song 1'), findsOneWidget);
    expect(find.text('Artist Song 2'), findsOneWidget);
    expect(repository.cursors, <String?>[null, 'artist-page-2']);
    expect(find.text('已经到底啦'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('整页都不属于当前歌手时会继续补取下一页', (tester) async {
    tester.view.physicalSize = const Size(375, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _UnrelatedFirstPageRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineMusicRepositoryProvider.overrideWithValue(repository),
          onlineTrackPlaybackProvider.overrideWithValue(_FakePlayback()),
          onlineSearchShowArtworkProvider.overrideWithValue(
            const AsyncData(false),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: OnlineCollectionPage(
              request: const OnlineCollectionRequest(
                kind: OnlineCollectionKind.artist,
                value: 'Artist B',
                seedTracks: [],
              ),
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Other Song'), findsNothing);
    expect(find.text('Artist Song 2'), findsOneWidget);
    expect(repository.cursors, <String?>[null, 'artist-page-2']);
    expect(tester.takeException(), isNull);
  });
}

OnlineTrack _track({
  required String id,
  required String title,
  required List<String> artists,
}) => OnlineTrack(
  provider: 'source-a',
  trackId: id,
  title: title,
  artists: artists,
  album: 'Album',
  playable: true,
  capabilities: const {'playback'},
);

class _PagedArtistRepository implements OnlineMusicSearchRepository {
  final cursors = <String?>[];

  @override
  Future<OnlineMusicSearchResult> search(String query, {String? cursor}) async {
    cursors.add(cursor);
    if (cursor == null) {
      return OnlineMusicSearchResult(
        items: [
          _track(
            id: 'artist-1',
            title: 'Artist Song 1',
            artists: const ['Artist B'],
          ),
        ],
        partial: false,
        warnings: const [],
        nextCursor: 'artist-page-2',
      );
    }
    return OnlineMusicSearchResult(
      items: [
        _track(
          id: 'artist-2',
          title: 'Artist Song 2',
          artists: const ['Artist B'],
        ),
      ],
      partial: false,
      warnings: const [],
    );
  }

  @override
  Future<Uint8List?> loadArtwork(OnlineTrack track) async => null;

  @override
  Future<String?> loadLyrics(OnlineTrack track) async => null;

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) =>
      throw UnimplementedError();
}

class _UnrelatedFirstPageRepository implements OnlineMusicSearchRepository {
  final cursors = <String?>[];

  @override
  Future<OnlineMusicSearchResult> search(String query, {String? cursor}) async {
    cursors.add(cursor);
    if (cursor == null) {
      return OnlineMusicSearchResult(
        items: [
          _track(
            id: 'other-1',
            title: 'Other Song',
            artists: const ['Artist C'],
          ),
        ],
        partial: false,
        warnings: const [],
        nextCursor: 'artist-page-2',
      );
    }
    return OnlineMusicSearchResult(
      items: [
        _track(
          id: 'artist-2',
          title: 'Artist Song 2',
          artists: const ['Artist B'],
        ),
      ],
      partial: false,
      warnings: const [],
    );
  }

  @override
  Future<Uint8List?> loadArtwork(OnlineTrack track) async => null;

  @override
  Future<String?> loadLyrics(OnlineTrack track) async => null;

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) =>
      throw UnimplementedError();
}

class _FakePlayback implements OnlineTrackPlayback {
  @override
  bool get supported => true;

  @override
  Future<void> play(OnlineTrack track) async {}
}
