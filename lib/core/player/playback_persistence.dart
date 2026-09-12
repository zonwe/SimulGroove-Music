import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:audio_service/audio_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';

import '../database/app_database.dart';
import '../log/app_log.dart';
import 'music_audio_handler.dart';
import 'saved_playback.dart';
import 'track_availability.dart';

class PlaybackPersistence with WidgetsBindingObserver {
  PlaybackPersistence(this._database, this._handler);

  final AppDatabase _database;
  final MusicAudioHandler _handler;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _timer;
  Future<void> _writes = Future.value();
  String? _lastWritten;
  bool _initialized = false;
  bool _disposed = false;

  Future<void> initialize() async {
    final revision = _handler.queueRevision;
    try {
      final row = await _database.readPlaybackSnapshot();
      if (row != null) {
        final saved = SavedPlayback.decode(
          queueJson: row.queueJson,
          currentId: row.trackId,
          positionMs: row.positionMs,
          repeatMode: row.repeatMode,
          shuffle: row.shuffle,
        );
        if (saved != null) {
          final tracks = (await _database.tracksByIds(saved.baseIds))
              .where(
                (track) =>
                    track.isAvailable &&
                    track.sourceType != 'online' &&
                    track.sourceType != 'synced',
              )
              .toList();
          // Restore a usable current track without probing the entire library.
          final byId = {for (final track in tracks) track.id: track};
          final candidates = [
            saved.currentId,
            ...saved.queueIds.where((id) => id != saved.currentId),
          ];
          String? current;
          for (final id in candidates) {
            final track = byId[id];
            if (track == null) continue;
            if (await checkTrackAvailability(track) == null) {
              current = id;
              break;
            }
            byId.remove(id);
          }
          if (current != null && !_disposed) {
            final track = byId[current]!;
            var position = current == saved.currentId
                ? saved.position
                : Duration.zero;
            final duration = track.durationMs;
            if (duration != null && position.inMilliseconds >= duration) {
              position = Duration.zero;
            }
            await _handler.restoreLocalQueue(
              byId.values.toList(),
              SavedPlayback(
                baseIds: saved.baseIds,
                queueIds: saved.queueIds,
                currentId: current,
                position: position,
                repeatMode: saved.repeatMode,
                shuffle: saved.shuffle,
              ),
              expectedRevision: revision,
            );
          }
        }
      }
    } catch (error, stackTrace) {
      AppLog.warning('恢复上次播放失败', error, stackTrace);
    }
    if (_disposed) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.add(
      _handler.playbackState.listen((_) => unawaited(saveNow())),
    );
    _subscriptions.add(_handler.queue.listen((_) => unawaited(saveNow())));
    _subscriptions.add(_handler.mediaItem.listen((_) => unawaited(saveNow())));
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(saveNow()),
    );
  }

  Future<void> saveNow() {
    if (!_initialized || _disposed) return _writes;
    final saved = _handler.savedPlayback;
    // Source loading can temporarily expose an empty queue; retain the last
    // complete snapshot until the handler has published its replacement.
    if (_handler.rebuildingQueue ||
        _handler.playbackState.value.processingState ==
            AudioProcessingState.loading) {
      return _writes;
    }
    final key = saved == null
        ? ''
        : '${saved.queueJson}|${saved.currentId}|${saved.position.inMilliseconds}|${saved.repeatMode.name}|${saved.shuffle}';
    _writes = _writes
        .then((_) async {
          if (_lastWritten == key) return;
          if (saved == null) {
            await _database.clearPlaybackSnapshot();
          } else {
            await _database.savePlaybackSnapshot(
              PlaybackSnapshotsCompanion.insert(
                trackId: Value(saved.currentId),
                queueJson: Value(saved.queueJson),
                positionMs: Value(saved.position.inMilliseconds),
                repeatMode: Value(saved.repeatMode.name),
                shuffle: Value(saved.shuffle),
                updatedAt: DateTime.now(),
              ),
            );
          }
          _lastWritten = key;
        })
        .catchError((Object error, StackTrace stackTrace) {
          AppLog.warning('保存播放进度失败', error, stackTrace);
        });
    return _writes;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(saveNow());
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await saveNow();
    return AppExitResponse.exit;
  }

  Future<void> dispose() async {
    await saveNow();
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
