import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_music/app/providers.dart';
import 'package:flutter_music/core/online_music/online_download_platform.dart';
import 'package:flutter_music/core/online_music/online_music_repository.dart';
import 'package:flutter_music/core/online_music/online_track.dart';
import 'package:flutter_music/core/online_music/online_track_downloader.dart';
import 'package:flutter_music/core/online_music/online_track_playback.dart';
import 'package:flutter_music/features/online_search/online_collection_page.dart';
import 'package:flutter_music/features/online_search/online_search_page.dart';
import 'package:flutter_music/features/shell/windows_title_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('右键菜单可打开歌手子菜单、专辑页和封面', (tester) async {
    OnlineCollectionRequest? opened;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineMusicRepositoryProvider.overrideWithValue(
            const _ContextMenuRepository(),
          ),
          onlineTrackPlaybackProvider.overrideWithValue(_FakePlayback()),
          onlineTrackDownloaderProvider.overrideWithValue(
            const _UnsupportedDownloader(),
          ),
          onlineSearchShowArtworkProvider.overrideWithValue(
            const AsyncData(false),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: OnlineSearchPage(
              onOpenCollection: (request) => opened = request,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Song');
    await tester.tap(find.byTooltip('立即搜索'));
    await tester.pumpAndSettle();

    await _openMenu(tester);
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.text('歌手：Artist A、Artist B'));
    await tester.pumpAndSettle();
    expect(find.text('Artist A'), findsOneWidget);
    expect(find.text('Artist B'), findsOneWidget);
    await tester.tap(find.text('Artist B'));
    await tester.pumpAndSettle();
    expect(opened?.kind, OnlineCollectionKind.artist);
    expect(opened?.value, 'Artist B');

    await _openMenu(tester);
    await tester.tap(find.text('专辑：Test Album'));
    await tester.pumpAndSettle();
    expect(opened?.kind, OnlineCollectionKind.album);
    expect(opened?.value, 'Test Album');

    await _openMenu(tester);
    await tester.tap(find.text('查看封面'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭封面'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭封面'));
    await tester.pumpAndSettle();
  });

  testWidgets('在线歌手集合页补搜、精确过滤并保留返回和播放', (tester) async {
    tester.view.physicalSize = const Size(375, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playback = _FakePlayback();
    var wentBack = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineMusicRepositoryProvider.overrideWithValue(
            const _CollectionRepository(),
          ),
          onlineTrackPlaybackProvider.overrideWithValue(playback),
          onlineSearchShowArtworkProvider.overrideWithValue(
            const AsyncData(false),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.6),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: OnlineCollectionPage(
                request: const OnlineCollectionRequest(
                  kind: OnlineCollectionKind.artist,
                  value: 'Artist B',
                  seedTracks: [_menuTrack],
                ),
                onBack: () => wentBack = true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('在线歌手'), findsOneWidget);
    expect(find.text('歌曲  2'), findsOneWidget);
    expect(find.text('Matching Song'), findsOneWidget);
    expect(find.text('Irrelevant Song'), findsNothing);
    await tester.tap(find.text('Matching Song'));
    await tester.pumpAndSettle();
    expect(playback.played.single.title, 'Matching Song');
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(780, 390);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(BackButton));
    expect(wentBack, isTrue);
  });

  testWidgets('独立在线集合页提供不透明背景和 Windows 拖动标题栏', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineMusicRepositoryProvider.overrideWithValue(
            const _CollectionRepository(),
          ),
          onlineTrackPlaybackProvider.overrideWithValue(_FakePlayback()),
          onlineSearchShowArtworkProvider.overrideWithValue(
            const AsyncData(false),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: OnlineCollectionPage(
            standalone: true,
            request: const OnlineCollectionRequest(
              kind: OnlineCollectionKind.artist,
              value: 'Artist B',
              seedTracks: [_menuTrack],
            ),
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(WindowsTitleBar), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final context = tester.element(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Theme.of(context).colorScheme.surface);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.text('Menu Song'), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

const _menuTrack = OnlineTrack(
  provider: 'source-a',
  trackId: 'menu-track',
  title: 'Menu Song',
  artists: ['Artist A', 'Artist B'],
  album: 'Test Album',
  playable: true,
  capabilities: {'playback', 'artwork'},
);

class _ContextMenuRepository implements OnlineMusicSearchRepository {
  const _ContextMenuRepository();

  @override
  Future<OnlineMusicSearchResult> search(
    String query, {
    String? cursor,
  }) async => const OnlineMusicSearchResult(
    items: [_menuTrack],
    partial: false,
    warnings: [],
  );

  @override
  Future<Uint8List?> loadArtwork(OnlineTrack track) async => null;

  @override
  Future<String?> loadLyrics(OnlineTrack track) async => null;

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) =>
      throw UnimplementedError();
}

class _CollectionRepository implements OnlineMusicSearchRepository {
  const _CollectionRepository();

  @override
  Future<OnlineMusicSearchResult> search(
    String query, {
    String? cursor,
  }) async => const OnlineMusicSearchResult(
    items: [
      OnlineTrack(
        provider: 'source-a',
        trackId: 'matching-track',
        title: 'Matching Song',
        artists: ['Artist B'],
        album: 'Another Album',
        playable: true,
        capabilities: {'playback'},
      ),
      OnlineTrack(
        provider: 'source-a',
        trackId: 'irrelevant-track',
        title: 'Irrelevant Song',
        artists: ['Other Artist'],
        album: 'Another Album',
        playable: true,
        capabilities: {'playback'},
      ),
    ],
    partial: false,
    warnings: [],
  );

  @override
  Future<Uint8List?> loadArtwork(OnlineTrack track) async => null;

  @override
  Future<String?> loadLyrics(OnlineTrack track) async => null;

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) =>
      throw UnimplementedError();
}

class _UnsupportedDownloader implements OnlineTrackDownloader {
  const _UnsupportedDownloader();

  @override
  bool get supported => false;

  @override
  Future<OnlineDownloadDestination?> chooseDestination() async => null;

  @override
  Future<OnlineDownloadDestination?> destination() async => null;

  @override
  Future<OnlineDownloadBatchResult> downloadAll(
    List<OnlineTrack> tracks, {
    void Function(OnlineDownloadProgress progress)? onProgress,
  }) => throw UnimplementedError();
}

class _FakePlayback implements OnlineTrackPlayback {
  final played = <OnlineTrack>[];

  @override
  bool get supported => true;

  @override
  Future<void> play(OnlineTrack track) async => played.add(track);
}
