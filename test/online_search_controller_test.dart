import 'dart:async';

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
  Future<OnlineMusicSearchResult> search(String query) async =>
      _results.removeAt(0);

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) =>
      throw UnimplementedError();
}

class _DeferredRepository implements OnlineMusicSearchRepository {
  final _requests = <String, Completer<OnlineMusicSearchResult>>{};

  void complete(String query, OnlineMusicSearchResult result) =>
      _requests[query]!.complete(result);

  @override
  Future<OnlineMusicSearchResult> search(String query) {
    final completer = Completer<OnlineMusicSearchResult>();
    _requests[query] = completer;
    return completer.future;
  }

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) =>
      throw UnimplementedError();
}

class _FailingRepository implements OnlineMusicSearchRepository {
  @override
  Future<OnlineMusicSearchResult> search(String query) =>
      Future.error(StateError('Service unavailable'));

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) =>
      throw UnimplementedError();
}
