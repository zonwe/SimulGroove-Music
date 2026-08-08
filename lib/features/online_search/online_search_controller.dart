import 'dart:async';

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
  });

  const OnlineSearchState.idle() : this(status: OnlineSearchStatus.idle);

  final OnlineSearchStatus status;
  final String query;
  final List<OnlineTrack> items;
  final List<OnlineMusicWarning> warnings;
  final String? message;
}

class OnlineSearchController extends ChangeNotifier {
  OnlineSearchController(
    this._repository, {
    Duration debounce = const Duration(milliseconds: 350),
  }) : _debounceDuration = debounce;

  final OnlineMusicSearchRepository _repository;
  final Duration _debounceDuration;
  Timer? _debounce;
  var _generation = 0;
  var _disposed = false;
  OnlineSearchState _state = const OnlineSearchState.idle();

  OnlineSearchState get state => _state;

  void queryChanged(String value) {
    _debounce?.cancel();
    final generation = ++_generation;
    final query = value.trim();
    if (query.isEmpty) {
      _setState(const OnlineSearchState.idle());
      return;
    }
    _setState(
      OnlineSearchState(
        status: _state.status,
        query: value,
        items: _state.items,
        warnings: _state.warnings,
        message: _state.message,
      ),
    );
    _debounce = Timer(_debounceDuration, () => _search(query, generation));
  }

  Future<void> searchNow(String value) async {
    _debounce?.cancel();
    final generation = ++_generation;
    final query = value.trim();
    if (query.isEmpty) {
      _setState(const OnlineSearchState.idle());
      return;
    }
    await _search(query, generation);
  }

  Future<void> retry() => searchNow(_state.query);

  Future<void> _search(String query, int generation) async {
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
    _debounce?.cancel();
    super.dispose();
  }
}
