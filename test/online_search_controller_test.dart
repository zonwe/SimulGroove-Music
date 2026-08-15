import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_music/core/online_music/online_music_repository.dart';
import 'package:flutter_music/core/online_music/online_track.dart';
import 'package:flutter_music/features/online_search/online_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('空结果和部分结果映射为明确状态', () async {
    final repository = _QueuedRepository();
    final controller = OnlineSearchController(repository);

    repository.completeNext(
      const OnlineMusicSearchResult(items: [], partial: false, warnings: []),
    );
    await controller.searchNow('missing');
    expect(controller.state.status, OnlineSearchStatus.empty);

    repository.completeNext(
      const OnlineMusicSearchResult(
        items: [
          OnlineTrack(
            provider: 'source-a',
            trackId: '1',
            title: 'Song',
            artists: ['Artist'],
            album: 'Album',
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
      ),
    );
    await controller.searchNow('Song');
    expect(controller.state.status, OnlineSearchStatus.partial);
    expect(controller.state.items.single.title, 'Song');

    controller.dispose();
  });

  test('较晚返回的旧请求不会覆盖新结果', () async {
    final repository = _DeferredRepository();
    final controller = OnlineSearchController(repository);

    final oldSearch = controller.searchNow('old');
    await Future<void>.delayed(Duration.zero);
    final newSearch = controller.searchNow('new');
    await Future<void>.delayed(Duration.zero);

    repository.complete('new', _result('New Song'));
    await newSearch;
    repository.complete('old', _result('Old Song'));
    await oldSearch;

    expect(controller.state.query, 'new');
    expect(controller.state.items.single.title, 'New Song');
    controller.dispose();
  });

  test('异常映射为可重试错误状态', () async {
    final controller = OnlineSearchController(_FailingRepository());

    await controller.searchNow('Song');

    expect(controller.state.status, OnlineSearchStatus.error);
    expect(controller.state.message, contains('Service unavailable'));
    controller.dispose();
  });

  test('清空输入会保持空闲并忽略尚未返回的搜索', () async {
    final repository = _DeferredRepository();
    final controller = OnlineSearchController(repository);

    final search = controller.searchNow('Song');
    await Future<void>.delayed(Duration.zero);
    controller.clear();
    repository.complete('Song', _result('Late Song'));
    await search;

    expect(controller.state.status, OnlineSearchStatus.idle);
    expect(controller.state.items, isEmpty);
    controller.dispose();
  });

  test('使用服务端游标前后翻页并维护页码', () async {
    final repository = _PagingRepository();
    final controller = OnlineSearchController(repository);

    await controller.searchNow('Song');
    expect(controller.state.page, 1);
    expect(controller.state.items.single.title, 'Page 1');
    expect(controller.state.hasPreviousPage, isFalse);
    expect(controller.state.hasNextPage, isTrue);

    await controller.nextPage();
    expect(controller.state.page, 2);
    expect(controller.state.items.single.title, 'Page 2');
    expect(controller.state.hasPreviousPage, isTrue);
    expect(controller.state.hasNextPage, isTrue);

    await controller.nextPage();
    expect(controller.state.page, 3);
    expect(controller.state.hasNextPage, isFalse);

    await controller.previousPage();
    await controller.previousPage();
    expect(controller.state.page, 1);
    expect(repository.cursors, <String?>[
      null,
      'cursor-2',
      'cursor-3',
      'cursor-2',
      null,
    ]);

    controller.dispose();
  });
}

OnlineMusicSearchResult _result(String title) => OnlineMusicSearchResult(
  items: [
    OnlineTrack(
      provider: 'source-a',
      trackId: title,
      title: title,
      artists: const ['Artist'],
      album: 'Album',
      playable: true,
      capabilities: const {'playback'},
    ),
  ],
  partial: false,
  warnings: const [],
);

class _QueuedRepository implements OnlineMusicSearchRepository {
  final _results = <OnlineMusicSearchResult>[];

  void completeNext(OnlineMusicSearchResult result) => _results.add(result);

  @override
  Future<OnlineMusicSearchResult> search(
    String query, {
    String? cursor,
  }) async => _results.removeAt(0);

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) =>
      throw UnimplementedError();

  @override
  Future<String?> loadLyrics(OnlineTrack track) async => null;

  @override
  Future<Uint8List?> loadArtwork(OnlineTrack track) async => null;
}

class _DeferredRepository implements OnlineMusicSearchRepository {
  final _requests = <String, Completer<OnlineMusicSearchResult>>{};

  void complete(String query, OnlineMusicSearchResult result) =>
      _requests[query]!.complete(result);

  @override
  Future<OnlineMusicSearchResult> search(String query, {String? cursor}) {
    final completer = Completer<OnlineMusicSearchResult>();
    _requests[query] = completer;
    return completer.future;
  }

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) =>
      throw UnimplementedError();

  @override
  Future<String?> loadLyrics(OnlineTrack track) async => null;

  @override
  Future<Uint8List?> loadArtwork(OnlineTrack track) async => null;
}

class _FailingRepository implements OnlineMusicSearchRepository {
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

class _PagingRepository implements OnlineMusicSearchRepository {
  final cursors = <String?>[];

  @override
  Future<OnlineMusicSearchResult> search(String query, {String? cursor}) async {
    cursors.add(cursor);
    return switch (cursor) {
      null => _pageResult('Page 1', 'cursor-2'),
      'cursor-2' => _pageResult('Page 2', 'cursor-3'),
      'cursor-3' => _pageResult('Page 3', null),
      _ => throw StateError('Unexpected cursor: $cursor'),
    };
  }

  @override
  Future<Uint8List?> loadArtwork(OnlineTrack track) async => null;

  @override
  Future<String?> loadLyrics(OnlineTrack track) async => null;

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) =>
      throw UnimplementedError();
}

OnlineMusicSearchResult _pageResult(String title, String? nextCursor) =>
    OnlineMusicSearchResult(
      items: [
        OnlineTrack(
          provider: 'source-a',
          trackId: title,
          title: title,
          artists: const ['Artist'],
          album: 'Album',
          playable: true,
          capabilities: const {'playback'},
        ),
      ],
      partial: false,
      warnings: const [],
      nextCursor: nextCursor,
    );
