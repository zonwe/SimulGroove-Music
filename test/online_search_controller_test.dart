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

  test('滚动到底部会追加下一页并保留已加载结果', () async {
    final repository = _PagingRepository();
    final controller = OnlineSearchController(repository);

    await controller.searchNow('Song');
    expect(controller.state.items.single.title, 'Page 1');
    expect(controller.state.hasMore, isTrue);

    await controller.loadMore();
    expect(_titles(controller), ['Page 1', 'Page 2']);
    expect(controller.state.hasMore, isTrue);

    await controller.loadMore();
    expect(_titles(controller), ['Page 1', 'Page 2', 'Page 3']);
    expect(controller.state.hasMore, isFalse);

    // 已经到底后重复触发不会再次请求服务端。
    await controller.loadMore();
    expect(repository.cursors, <String?>[null, 'cursor-2', 'cursor-3']);

    // 新的搜索会清空已累计的结果。
    await controller.searchNow('Song');
    expect(controller.state.items.single.title, 'Page 1');
    expect(controller.state.hasMore, isTrue);

    controller.dispose();
  });

  test('加载下一页失败时保留已加载结果并提示重试', () async {
    final repository = _PagingRepository(failOn: 'cursor-2');
    final controller = OnlineSearchController(repository);

    await controller.searchNow('Song');
    await controller.loadMore();

    expect(controller.state.items.single.title, 'Page 1');
    expect(controller.state.hasMore, isTrue);
    expect(controller.state.isLoadingMore, isFalse);
    expect(controller.state.loadMoreMessage, contains('Service unavailable'));
    expect(controller.state.loadMoreMessageIsError, isTrue);

    controller.dispose();
  });

  test('跨页重复的歌曲只保留一份', () async {
    final controller = OnlineSearchController(_OverlappingRepository());

    await controller.searchNow('Song');
    await controller.loadMore();

    expect(_titles(controller), ['Shared Song', 'Second Song']);
    expect(controller.state.hasMore, isFalse);

    controller.dispose();
  });
}

List<String> _titles(OnlineSearchController controller) =>
    controller.state.items.map((track) => track.title).toList();

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
  _PagingRepository({this.failOn});

  final String? failOn;
  final cursors = <String?>[];

  @override
  Future<OnlineMusicSearchResult> search(String query, {String? cursor}) async {
    cursors.add(cursor);
    if (cursor != null && cursor == failOn) {
      throw StateError('Service unavailable');
    }
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

class _OverlappingRepository implements OnlineMusicSearchRepository {
  @override
  Future<OnlineMusicSearchResult> search(String query, {String? cursor}) async {
    if (cursor == null) {
      return OnlineMusicSearchResult(
        items: [_track('shared', 'Shared Song')],
        partial: false,
        warnings: const [],
        nextCursor: 'cursor-2',
      );
    }
    return OnlineMusicSearchResult(
      items: [_track('shared', 'Shared Song'), _track('second', 'Second Song')],
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

OnlineTrack _track(String id, String title) => OnlineTrack(
  provider: 'source-a',
  trackId: id,
  title: title,
  artists: const ['Artist'],
  album: 'Album',
  playable: true,
  capabilities: const {'playback'},
);

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
