import 'package:flutter/foundation.dart';

import '../../core/online_music/online_music_repository.dart';
import '../../core/online_music/online_track.dart';

enum OnlineSearchStatus { idle, loading, data, empty, partial, error }

class OnlineSearchState {
  const OnlineSearchState({
    required this.status,
    this.query = '',
    this.items = const [],
    this.warnings = const [],
    this.message,
    this.nextCursor,
    this.isLoadingMore = false,
    this.loadMoreMessage,
    this.loadMoreMessageIsError = false,
  });

  const OnlineSearchState.idle() : this(status: OnlineSearchStatus.idle);

  final OnlineSearchStatus status;
  final String query;

  /// 已经累计加载的结果：滚动到底部后继续追加，而不是替换整页。
  final List<OnlineTrack> items;
  final List<OnlineMusicWarning> warnings;
  final String? message;

  /// 服务端返回的下一页游标；为空表示已经到底。
  final String? nextCursor;
  final bool isLoadingMore;
  final String? loadMoreMessage;
  final bool loadMoreMessageIsError;

  bool get hasMore => nextCursor?.trim().isNotEmpty ?? false;
}

class OnlineSearchController extends ChangeNotifier {
  OnlineSearchController(this._repository);

  final OnlineMusicSearchRepository _repository;
  var _generation = 0;
  var _disposed = false;
  OnlineSearchState _state = const OnlineSearchState.idle();

  OnlineSearchState get state => _state;

  void clear() {
    _generation++;
    _setState(const OnlineSearchState.idle());
  }

  Future<void> searchNow(String value) async {
    final generation = ++_generation;
    final query = value.trim();
    if (query.isEmpty) {
      _setState(const OnlineSearchState.idle());
      return;
    }
    await _loadFirstPage(query, generation);
  }

  Future<void> retry() => searchNow(_state.query);

  /// 滚动到底部时加载下一页，并把新结果追加到现有列表。
  ///
  /// 重复触发是安全的：加载中或已经到底时直接返回。
  Future<void> loadMore() async {
    final current = _state;
    if (current.isLoadingMore || !current.hasMore) return;
    final cursor = current.nextCursor;
    if (cursor == null) return;
    final generation = ++_generation;
    _setState(
      OnlineSearchState(
        status: current.status,
        query: current.query,
        items: current.items,
        warnings: current.warnings,
        message: current.message,
        nextCursor: current.nextCursor,
        isLoadingMore: true,
      ),
    );
    try {
      final result = await _repository.search(current.query, cursor: cursor);
      if (!_isCurrent(generation)) return;
      final items = _appendUnique(current.items, result.items);
      // 空页或游标没有前进都视为到底，避免在坏数据上反复请求。
      final reachedEnd = result.items.isEmpty || result.nextCursor == cursor;
      final warnings = _mergeWarnings(current.warnings, result.warnings);
      _setState(
        OnlineSearchState(
          status: items.isEmpty
              ? OnlineSearchStatus.empty
              : warnings.isEmpty
              ? OnlineSearchStatus.data
              : OnlineSearchStatus.partial,
          query: current.query,
          items: items,
          warnings: warnings,
          nextCursor: reachedEnd ? null : result.nextCursor,
          loadMoreMessage: reachedEnd ? '没有更多搜索结果了。' : null,
        ),
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _setState(
        OnlineSearchState(
          status: current.status,
          query: current.query,
          items: current.items,
          warnings: current.warnings,
          message: current.message,
          nextCursor: current.nextCursor,
          loadMoreMessage: '加载更多失败：$error',
          loadMoreMessageIsError: true,
        ),
      );
    }
  }

  Future<void> _loadFirstPage(String query, int generation) async {
    if (!_isCurrent(generation)) return;
    _setState(
      OnlineSearchState(status: OnlineSearchStatus.loading, query: query),
    );
    try {
      final result = await _repository.search(query);
      if (!_isCurrent(generation)) return;
      final status = result.items.isEmpty
          ? OnlineSearchStatus.empty
          : result.partial || result.warnings.isNotEmpty
          ? OnlineSearchStatus.partial
          : OnlineSearchStatus.data;
      _setState(
        OnlineSearchState(
          status: status,
          query: query,
          items: result.items,
          warnings: result.warnings,
          nextCursor: result.items.isEmpty ? null : result.nextCursor,
        ),
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _setState(
        OnlineSearchState(
          status: OnlineSearchStatus.error,
          query: query,
          message: error.toString(),
        ),
      );
    }
  }

  List<OnlineTrack> _appendUnique(
    List<OnlineTrack> existing,
    List<OnlineTrack> incoming,
  ) {
    final seen = {for (final track in existing) track.id};
    final merged = List<OnlineTrack>.of(existing);
    for (final track in incoming) {
      if (seen.add(track.id)) merged.add(track);
    }
    return List.unmodifiable(merged);
  }

  List<OnlineMusicWarning> _mergeWarnings(
    List<OnlineMusicWarning> existing,
    List<OnlineMusicWarning> incoming,
  ) {
    if (incoming.isEmpty) return existing;
    final keys = {
      for (final warning in existing) '${warning.provider}:${warning.code}',
    };
    final merged = List<OnlineMusicWarning>.of(existing);
    for (final warning in incoming) {
      if (keys.add('${warning.provider}:${warning.code}')) merged.add(warning);
    }
    return List.unmodifiable(merged);
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _setState(OnlineSearchState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
