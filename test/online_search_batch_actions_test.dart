import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_music/app/providers.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/core/online_music/online_download_platform.dart';
import 'package:flutter_music/core/online_music/online_music_repository.dart';
import 'package:flutter_music/core/online_music/online_track.dart';
import 'package:flutter_music/core/online_music/online_track_downloader.dart';
import 'package:flutter_music/core/online_music/online_track_playback.dart';
import 'package:flutter_music/features/online_search/online_search_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('搜索结果可选择后下载并批量新建歌单', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final downloader = _FakeDownloader();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          onlineMusicRepositoryProvider.overrideWithValue(
            const _ResultRepository(),
          ),
          onlineTrackPlaybackProvider.overrideWithValue(const _FakePlayback()),
          onlineTrackDownloaderProvider.overrideWithValue(downloader),
        ],
        child: const MaterialApp(home: Scaffold(body: OnlineSearchPage())),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Song');
    await tester.tap(find.byTooltip('立即搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);

    await tester.tap(find.text('Test Song'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('下载单曲'), findsOneWidget);
    await tester.tap(find.text('下载单曲'));
    await tester.pumpAndSettle();
    expect(downloader.downloaded.single.title, 'Test Song');
    expect(find.byType(Checkbox), findsNothing);
    downloader.downloaded.clear();

    await tester.longPress(find.text('Test Song'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('选中'), findsOneWidget);
    await tester.tap(find.text('选中'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text('下载 1 首'), findsOneWidget);

    await tester.tap(find.text('下载 1 首'));
    await tester.pump();
    expect(downloader.downloaded.single.title, 'Test Song');
    expect(find.byType(Checkbox), findsNothing);

    await tester.tap(find.text('Test Song'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.text('选中'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.text('加入新歌单'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '搜索收藏');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已新建歌单“搜索收藏”'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await database.close();
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

class _FakeDownloader implements OnlineTrackDownloader {
  final downloaded = <OnlineTrack>[];
  OnlineDownloadDestination? _destination = const OnlineDownloadDestination(
    uri: 'test://downloads',
    label: '测试下载目录',
  );

  @override
  bool get supported => true;

  @override
  Future<OnlineDownloadDestination?> chooseDestination() async => _destination =
      const OnlineDownloadDestination(uri: 'test://downloads', label: '测试下载目录');

  @override
  Future<OnlineDownloadDestination?> destination() async => _destination;

  @override
  Future<OnlineDownloadBatchResult> downloadAll(
    List<OnlineTrack> tracks, {
    void Function(OnlineDownloadProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      OnlineDownloadProgress(completed: 0, total: tracks.length),
    );
    downloaded.addAll(tracks);
    onProgress?.call(
      OnlineDownloadProgress(completed: tracks.length, total: tracks.length),
    );
    return OnlineDownloadBatchResult(downloaded: tracks, failures: const []);
  }
}

class _FakePlayback implements OnlineTrackPlayback {
  const _FakePlayback();

  @override
  bool get supported => true;

  @override
  Future<void> play(OnlineTrack track) async {}
}
