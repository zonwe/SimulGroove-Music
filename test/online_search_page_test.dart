import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_music/app/providers.dart';
import 'package:flutter_music/core/online_music/online_music_repository.dart';
import 'package:flutter_music/core/online_music/online_track.dart';
import 'package:flutter_music/core/online_music/online_track_playback.dart';
import 'package:flutter_music/features/online_search/online_search_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('窄屏会展示空闲状态和部分搜索结果', (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final playback = _FakePlayback();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineMusicRepositoryProvider.overrideWithValue(
            const _ResultRepository(),
          ),
          onlineTrackPlaybackProvider.overrideWithValue(playback),
          onlineSearchShowArtworkProvider.overrideWithValue(
            const AsyncData(true),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: OnlineSearchPage())),
      ),
    );

    expect(find.text('输入关键字后点击搜索'), findsNWidgets(2));
    await tester.enterText(find.byType(TextField), 'Song');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Test Song'), findsNothing);
    await tester.tap(find.byTooltip('立即搜索'));
    await tester.pumpAndSettle();

    expect(find.text('Test Song'), findsOneWidget);
    expect(find.textContaining('source-b 暂时不可用'), findsOneWidget);
    expect(find.byTooltip('播放 Test Song'), findsNothing);
    final resultsViewport = tester.getRect(find.byType(SingleChildScrollView));
    final resultCard = tester.getRect(
      find.ancestor(of: find.text('Test Song'), matching: find.byType(Card)),
    );
    expect(resultsViewport.right - resultCard.right, 16);
    await tester.tap(find.text('Test Song'));
    await tester.pumpAndSettle();
    expect(playback.played.single.title, 'Test Song');
    expect(tester.takeException(), isNull);
  });

  testWidgets('错误状态提供可访问的重试操作', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineMusicRepositoryProvider.overrideWithValue(
            const _ErrorRepository(),
          ),
          onlineTrackPlaybackProvider.overrideWithValue(_FakePlayback()),
          onlineSearchShowArtworkProvider.overrideWithValue(
            const AsyncData(true),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: OnlineSearchPage())),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Song');
    await tester.tap(find.byTooltip('立即搜索'));
    await tester.pumpAndSettle();

    expect(find.text('在线搜索失败'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
  });

  testWidgets('深色横屏和大字体下不会布局溢出', (tester) async {
    tester.view.physicalSize = const Size(780, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineMusicRepositoryProvider.overrideWithValue(
            const _ResultRepository(),
          ),
          onlineTrackPlaybackProvider.overrideWithValue(_FakePlayback()),
          onlineSearchShowArtworkProvider.overrideWithValue(
            const AsyncData(true),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Scaffold(body: OnlineSearchPage()),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Song');
    await tester.tap(find.byTooltip('立即搜索'));
    await tester.pumpAndSettle();

    expect(find.text('Test Song'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('页面重新挂载后保留搜索词和结果', (tester) async {
    var showSearch = true;
    late StateSetter setHostState;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineMusicRepositoryProvider.overrideWithValue(
            const _ResultRepository(),
          ),
          onlineTrackPlaybackProvider.overrideWithValue(_FakePlayback()),
          onlineSearchShowArtworkProvider.overrideWithValue(
            const AsyncData(true),
          ),
        ],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return Scaffold(
                body: showSearch
                    ? const OnlineSearchPage()
                    : const Text('其他页面'),
              );
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Song');
    await tester.tap(find.byTooltip('立即搜索'));
    await tester.pumpAndSettle();
    expect(find.text('Test Song'), findsOneWidget);

    setHostState(() => showSearch = false);
    await tester.pump();
    expect(find.text('其他页面'), findsOneWidget);

    setHostState(() => showSearch = true);
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Song'), findsOneWidget);
    expect(find.text('Test Song'), findsOneWidget);
  });

  testWidgets('关闭搜索封面后不展示也不请求封面', (tester) async {
    final repository = _ArtworkResultRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineMusicRepositoryProvider.overrideWithValue(repository),
          onlineTrackPlaybackProvider.overrideWithValue(_FakePlayback()),
          onlineSearchShowArtworkProvider.overrideWithValue(
            const AsyncData(false),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: OnlineSearchPage())),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Song');
    await tester.tap(find.byTooltip('立即搜索'));
    await tester.pumpAndSettle();

    expect(find.text('Artwork Song'), findsOneWidget);
    expect(find.byIcon(Icons.music_note_rounded), findsNothing);
    expect(repository.artworkCalls, 0);
  });

  testWidgets('搜索结果可使用上一页和下一页翻页', (tester) async {
    tester.view.physicalSize = const Size(375, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _PagedResultRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineMusicRepositoryProvider.overrideWithValue(repository),
          onlineTrackPlaybackProvider.overrideWithValue(_FakePlayback()),
          onlineSearchShowArtworkProvider.overrideWithValue(
            const AsyncData(true),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: OnlineSearchPage())),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Song');
    await tester.tap(find.byTooltip('立即搜索'));
    await tester.pumpAndSettle();

    expect(find.text('Page 1 Song'), findsOneWidget);
    expect(find.text('第 1 页'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '下一页'));
    await tester.pumpAndSettle();

    expect(find.text('Page 2 Song'), findsOneWidget);
    expect(find.text('第 2 页'), findsOneWidget);
    expect(repository.cursors, <String?>[null, 'next-page']);

    await tester.tap(find.widgetWithText(OutlinedButton, '上一页'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 Song'), findsOneWidget);
    expect(repository.cursors, <String?>[null, 'next-page', null]);
  });
}

class _ResultRepository implements OnlineMusicSearchRepository {
  const _ResultRepository();

  @override
  Future<OnlineMusicSearchResult> search(
    String query, {
    String? cursor,
  }) async => const OnlineMusicSearchResult(
    items: [
      OnlineTrack(
        provider: 'source-a',
        trackId: 'track-1',
        title: 'Test Song',
        artists: ['Test Artist'],
        album: 'Test Album',
        playable: true,
        capabilities: {'playback'},
      ),
    ],
    partial: true,
    warnings: [
      OnlineMusicWarning(
        provider: 'source-b',
        code: 'online_music_source_unavailable',
        message: 'Unavailable',
      ),
    ],
  );

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) =>
      throw UnimplementedError();

  @override
  Future<String?> loadLyrics(OnlineTrack track) async => null;

  @override
  Future<Uint8List?> loadArtwork(OnlineTrack track) async => null;
}

class _ErrorRepository implements OnlineMusicSearchRepository {
  const _ErrorRepository();

  @override
  Future<OnlineMusicSearchResult> search(String query, {String? cursor}) =>
      Future.error(StateError('Service unavailable'));

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) =>
      throw UnimplementedError();

  @override
  Future<String?> loadLyrics(OnlineTrack track) async => null;

  @override
  Future<Uint8List?> loadArtwork(OnlineTrack track) async => null;
}

class _ArtworkResultRepository implements OnlineMusicSearchRepository {
  var artworkCalls = 0;

  @override
  Future<OnlineMusicSearchResult> search(
    String query, {
    String? cursor,
  }) async => const OnlineMusicSearchResult(
    items: [
      OnlineTrack(
        provider: 'source-a',
        trackId: 'artwork-track',
        title: 'Artwork Song',
        artists: ['Test Artist'],
        album: 'Test Album',
        playable: true,
        capabilities: {'playback', 'artwork'},
      ),
    ],
    partial: false,
    warnings: [],
  );

  @override
  Future<Uint8List?> loadArtwork(OnlineTrack track) async {
    artworkCalls++;
    return null;
  }

  @override
  Future<String?> loadLyrics(OnlineTrack track) async => null;

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) =>
      throw UnimplementedError();
}

class _PagedResultRepository implements OnlineMusicSearchRepository {
  final cursors = <String?>[];

  @override
  Future<OnlineMusicSearchResult> search(String query, {String? cursor}) async {
    cursors.add(cursor);
    final firstPage = cursor == null;
    return OnlineMusicSearchResult(
      items: [
        OnlineTrack(
          provider: 'source-a',
          trackId: firstPage ? 'page-1' : 'page-2',
          title: firstPage ? 'Page 1 Song' : 'Page 2 Song',
          artists: const ['Artist'],
          album: 'Album',
          playable: true,
          capabilities: const {'playback'},
        ),
      ],
      partial: false,
      warnings: const [],
      nextCursor: firstPage ? 'next-page' : null,
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
  final played = <OnlineTrack>[];

  @override
  bool get supported => true;

  @override
  Future<void> play(OnlineTrack track) async => played.add(track);
}
