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
    this.page = 1,
    this.isPageLoading = false,
    this.pageMessage,
    this.pageMessageIsError = false,
  });

  const OnlineSearchState.idle() : this(status: OnlineSearchStatus.idle);

  final OnlineSearchStatus status;
  final String query;
  final List<OnlineTrack> items;
  final List<OnlineMusicWarning> warnings;
  final String? message;
  final String? nextCursor;
  final int page;
  final bool isPageLoading;
  final String? pageMessage;
  final bool pageMessageIsError;

  bool get hasPreviousPage => page > 1;
  bool get hasNextPage => nextCursor?.trim().isNotEmpty ?? false;
}

class OnlineSearchController extends ChangeNotifier {
  OnlineSearchController(this._repository);

  final OnlineMusicSearchRepository _repository;
  final List<String?> _pageCursors = [null];
  var _generation = 0;
  var _disposed = false;
  OnlineSearchState _state = const OnlineSearchState.idle();

  OnlineSearchState get state => _state;

  void clear() {
    _generation++;
    _resetPages();
    _setState(const OnlineSearchState.idle());
  }

  Future<void> searchNow(String value) async {
    final generation = ++_generation;
    final query = value.trim();
    if (query.isEmpty) {
      _resetPages();
      _setState(const OnlineSearchState.idle());
      return;
    }
    _resetPages();
    await _search(query, generation, cursor: null, page: 1, initial: true);
  }

  Future<void> retry() => searchNow(_state.query);

  Future<void> nextPage() async {
    if (_state.isPageLoading || !_state.hasNextPage) return;
    final cursor = _state.nextCursor;
    if (cursor == null) return;
    final generation = ++_generation;
    await _search(
      _state.query,
      generation,
      cursor: cursor,
      page: _state.page + 1,
      initial: false,
    );
  }

  Future<void> previousPage() async {
    if (_state.isPageLoading || !_state.hasPreviousPage) return;
    final page = _state.page - 1;
    final generation = ++_generation;
    await _search(
      _state.query,
      generation,
      cursor: _pageCursors[page - 1],
      page: page,
      initial: false,
    );
  }

  Future<void> _search(
    String query,
    int generation, {
    required String? cursor,
    required int page,
    required bool initial,
  }) async {
    if (!_isCurrent(generation)) return;
    final previous = _state;
    if (initial) {
      _setState(
        OnlineSearchState(status: OnlineSearchStatus.loading, query: query),
      );
    } else {
      _setState(
        OnlineSearchState(
          status: previous.status,
          query: previous.query,
          items: previous.items,
          warnings: previous.warnings,
          message: previous.message,
          nextCursor: previous.nextCursor,
          page: previous.page,
          isPageLoading: true,
        ),
      );
    }
    try {
      final result = await _repository.search(query, cursor: cursor);
      if (!_isCurrent(generation)) return;
      if (!initial && result.items.isEmpty) {
        _setState(
          OnlineSearchState(
            status: previous.status,
            query: previous.query,
            items: previous.items,
            warnings: previous.warnings,
            message: previous.message,
            page: previous.page,
            pageMessage: '没有更多搜索结果。',
          ),
        );
        return;
      }
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
          nextCursor: result.nextCursor,
          page: page,
        ),
      );
      _rememberCursor(page, cursor);
    } catch (error) {
      if (!_isCurrent(generation)) return;
      if (!initial) {
        _setState(
          OnlineSearchState(
            status: previous.status,
            query: previous.query,
            items: previous.items,
            warnings: previous.warnings,
            message: previous.message,
            nextCursor: previous.nextCursor,
            page: previous.page,
            pageMessage: '翻页失败：$error',
            pageMessageIsError: true,
          ),
        );
        return;
      }
      _setState(
        OnlineSearchState(
          status: OnlineSearchStatus.error,
          query: query,
          message: error.toString(),
        ),
      );
    }
  }

  void _resetPages() {
    _pageCursors
      ..clear()
      ..add(null);
  }

  void _rememberCursor(int page, String? cursor) {
    final index = page - 1;
    if (_pageCursors.length > index) {
      _pageCursors[index] = cursor;
    } else {
      _pageCursors.add(cursor);
    }
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
