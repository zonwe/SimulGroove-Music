import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../database/app_database.dart';
import '../log/app_log.dart';
import 'artwork_cache.dart';
import 'equalizer_controller.dart';
import 'local_audio_source.dart';
import 'playback_queue_logic.dart';
import 'volume_state.dart';
import 'saved_playback.dart';

export 'playback_queue_logic.dart' show PlaybackMode;

class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MusicAudioHandler({
    ja.AudioPlayer? player,
    Future<Uint8List?> Function(String trackId)? loadArtwork,
  }) : _player = player ?? _createPlayer(),
       _artworkLoader = loadArtwork {
    _subscriptions.add(
      _player.playbackEventStream.listen(
        _handlePlaybackEvent,
        onError: _reportPlaybackError,
      ),
    );
    _subscriptions.add(
      _player.playingStream.listen((_) {
        // just_audio publishes `playing` independently from PlaybackEvent.
        // Keep audio_service in sync so Android can activate its MediaSession
        // and promote the playback service to the foreground immediately.
        _broadcastState(_player.playbackEvent);
      }),
    );
    _subscriptions.add(_player.currentIndexStream.listen(_updateCurrentItem));
  }

  final EqualizerController _equalizer = EqualizerController();

  static ja.AudioPlayer _createPlayer() => ja.AudioPlayer(
    audioPipeline: sharedAndroidEqualizer != null
        ? ja.AudioPipeline(androidAudioEffects: [sharedAndroidEqualizer!])
        : null,
  );
  final ja.AudioPlayer _player;

  /// 按曲目 id 读取封面。封面已拆到独立表，队列不再一次性把整库封面带进内存，
  /// 只在当前曲目切换时按需取一张。
  final Future<Uint8List?> Function(String trackId)? _artworkLoader;
  final Set<String> _artworkLoading = {};
  final _errors = StreamController<String>.broadcast();
  int _queueRequest = 0;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Random _random = Random();
  List<Track> _tracks = const [];
  List<MediaItem> _items = const [];
  List<int> _baseOrder = const [];
  List<int> _activeOrder = const [];
  bool _shuffleEnabled = false;
  bool _rebuildingQueue = false;
  bool _changingPlaybackMode = false;
  bool _restartingListLoop = false;
  double _volumeBeforeMute = 1;
  bool _muted = false;

  bool get equalizerEnabled => _equalizer.enabled;
  List<double> get equalizerGains => _equalizer.gains;
  double get equalizerPreampDb => _equalizer.preampDb;
  String get equalizerPresetId => _equalizer.presetId;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<ja.PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<double> get volumeStream => _player.volumeStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  Stream<String> get errors => _errors.stream;
  int get queueRevision => _queueRequest;
  bool get rebuildingQueue => _rebuildingQueue;

  SavedPlayback? get savedPlayback {
    final currentId = mediaItem.value?.id;
    if (_rebuildingQueue || _tracks.isEmpty || currentId == null) return null;
    return SavedPlayback(
      baseIds: _tracks.map((track) => track.id),
      queueIds: queue.value.map((item) => item.id),
      currentId: currentId,
      position: _player.position,
      repeatMode: playbackState.value.repeatMode,
      shuffle: _shuffleEnabled,
    );
  }

  Future<void> playTracks(List<Track> tracks, {int initialIndex = 0}) =>
      _loadLocalQueue(tracks, initialIndex: initialIndex);

  Future<void> restoreLocalQueue(
    List<Track> tracks,
    SavedPlayback saved, {
    required int expectedRevision,
  }) async {
    if (_queueRequest != expectedRevision || queue.value.isNotEmpty) return;
    final byId = {for (final track in tracks) track.id: track};
    final base = [for (final id in saved.baseIds) ?byId[id]];
    final indices = {for (var i = 0; i < base.length; i++) base[i].id: i};
    final order = [for (final id in saved.queueIds) ?indices[id]];
    if (order.isEmpty) return;
    final current = saved.queueIds
        .where(indices.containsKey)
        .toList()
        .indexOf(saved.currentId);
    await _loadLocalQueue(
      base,
      initialIndex: current < 0 ? 0 : current,
      order: order,
      initialPosition: current < 0 ? Duration.zero : saved.position,
      playWhenReady: false,
      shuffle: saved.shuffle,
      repeatMode: saved.repeatMode,
    );
  }

  Future<void> _loadLocalQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    List<int>? order,
    Duration initialPosition = Duration.zero,
    bool playWhenReady = true,
    bool shuffle = false,
    AudioServiceRepeatMode? repeatMode,
  }) async {
    if (tracks.isEmpty || initialIndex < 0 || initialIndex >= tracks.length) {
      return;
    }
    final request = ++_queueRequest;
    final items = tracks.map(_toMediaItem).toList(growable: false);
    final activeOrder =
        order ?? List<int>.generate(tracks.length, (index) => index);
    final sources = await Future.wait(
      activeOrder.map(
        (index) => createAudioSource(tracks[index], items[index]),
      ),
    );
    if (request != _queueRequest) return;
    _rebuildingQueue = true;
    try {
      await _player.setAudioSources(
        sources,
        initialIndex: initialIndex,
        initialPosition: initialPosition,
      );
      if (request == _queueRequest && repeatMode != null) {
        await _player.setLoopMode(audioServiceRepeatToLoopMode(repeatMode));
      }
    } finally {
      if (request == _queueRequest) _rebuildingQueue = false;
    }
    if (request != _queueRequest) return;
    _tracks = List<Track>.unmodifiable(tracks);
    _items = List<MediaItem>.unmodifiable(items);
    _baseOrder = List<int>.generate(tracks.length, (index) => index);
    _activeOrder = List<int>.of(activeOrder);
    _shuffleEnabled = shuffle;
    queue.add([for (final index in activeOrder) items[index]]);
    _updateCurrentItem(initialIndex);
    _broadcastState(_player.playbackEvent);
    if (playWhenReady) await play();
  }

  Future<void> playOnlineTrack({
    required String id,
    required String title,
    required String artist,
    required String album,
    required String provider,
    required String trackId,
    required Uri uri,
    required Map<String, String> headers,
    String? lyrics,
    Uint8List? artwork,
    int? durationMs,
  }) async {
    final request = ++_queueRequest;
    final item = MediaItem(
      id: 'online:$id',
      title: title,
      artist: artist.isEmpty ? '未知艺术家' : artist,
      album: album,
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
      extras: {
        'uri': uri.toString(),
        'sourceType': 'online',
        'provider': provider,
        'trackId': trackId,
        'lyrics': lyrics,
        'artwork': artwork,
      },
    );
    final source = ja.AudioSource.uri(uri, headers: headers, tag: item);
    _rebuildingQueue = true;
    try {
      await _player.setAudioSources(
        [source],
        initialIndex: 0,
        initialPosition: Duration.zero,
      );
    } finally {
      if (request == _queueRequest) _rebuildingQueue = false;
    }
    if (request != _queueRequest) return;
    _tracks = const [];
    _items = [item];
    _baseOrder = const [0];
    _activeOrder = const [0];
    _shuffleEnabled = false;
    queue.add([item]);
    _updateCurrentItem(0);
    _broadcastState(_player.playbackEvent);
    await play();
  }

  MediaItem _toMediaItem(Track track, [Uint8List? artwork]) {
    return MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.durationMs == null
          ? null
          : Duration(milliseconds: track.durationMs!),
      extras: {
        'uri': track.uri,
        'lyrics': track.lyrics,
        'sourceType': track.sourceType,
        'artwork': artwork,
      },
    );
  }

  void _updateCurrentItem(int? index) {
    if (_rebuildingQueue) return;
    final items = queue.value;
    if (index != null && index >= 0 && index < items.length) {
      final item = items[index];
      mediaItem.add(item);
      final bytes = item.extras?['artwork'];
      if (item.artUri == null && bytes is Uint8List) {
        unawaited(_cacheCurrentArtwork(item.id, bytes, _queueRequest));
      } else if (bytes == null) {
        _ensureCurrentArtwork(item);
      }
    }
  }

  /// 懒加载当前曲目的封面：先补进队列项（供正在播放页使用），再写入通知缓存。
  void _ensureCurrentArtwork(MediaItem item) {
    final loader = _artworkLoader;
    if (loader == null || !_artworkLoading.add(item.id)) return;
    final request = _queueRequest;
    unawaited(() async {
      try {
        final bytes = await loader(item.id);
        if (bytes == null || request != _queueRequest) return;
        final current = mediaItem.value;
        if (current?.id != item.id) return;
        _replaceItem(
          current!.copyWith(extras: {...?current.extras, 'artwork': bytes}),
        );
        if (current.artUri == null) {
          await _cacheCurrentArtwork(current.id, bytes, request);
        }
      } catch (error, stackTrace) {
        AppLog.warning('读取曲目封面失败', error, stackTrace);
      } finally {
        _artworkLoading.remove(item.id);
      }
    }());
  }

  Future<void> updateOnlineTrackMetadata({
    required String id,
    String? lyrics,
    Uint8List? artwork,
  }) async {
    final current = mediaItem.value;
    if (current?.id != 'online:$id' ||
        current?.extras?['sourceType'] != 'online') {
      return;
    }
    _replaceItem(
      current!.copyWith(
        extras: {...?current.extras, 'lyrics': ?lyrics, 'artwork': ?artwork},
      ),
    );
    if (artwork != null) {
      await _cacheCurrentArtwork(current.id, artwork, _queueRequest);
    }
  }

  Future<void> _cacheCurrentArtwork(
    String id,
    Uint8List bytes,
    int request,
  ) async {
    try {
      final artUri = await cacheArtwork(id, bytes);
      final current = mediaItem.value;
      if (request != _queueRequest || current?.id != id || artUri == null) {
        return;
      }
      _replaceItem(current!.copyWith(artUri: artUri));
    } catch (error, stackTrace) {
      AppLog.warning('播放器封面缓存失败', error, stackTrace);
    }
  }

  void _replaceItem(MediaItem updated) {
    _items = [
      for (final item in _items)
        if (item.id == updated.id) updated else item,
    ];
    queue.add([
      for (final item in queue.value)
        if (item.id == updated.id) updated else item,
    ]);
    mediaItem.add(updated);
  }

  void _broadcastState(ja.PlaybackEvent event) {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          _player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ja.ProcessingState.idle => AudioProcessingState.idle,
          ja.ProcessingState.loading => AudioProcessingState.loading,
          ja.ProcessingState.buffering => AudioProcessingState.buffering,
          ja.ProcessingState.ready => AudioProcessingState.ready,
          ja.ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex ?? _player.currentIndex,
        repeatMode: switch (_player.loopMode) {
          ja.LoopMode.off => AudioServiceRepeatMode.none,
          ja.LoopMode.one => AudioServiceRepeatMode.one,
          ja.LoopMode.all => AudioServiceRepeatMode.all,
        },
        shuffleMode: _shuffleEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  void _handlePlaybackEvent(ja.PlaybackEvent event) {
    _broadcastState(event);

    if (!shouldRestartListLoop(
      processingState: event.processingState,
      loopMode: _player.loopMode,
      rebuildingQueue: _rebuildingQueue,
      restartingListLoop: _restartingListLoop,
      queueLength: queue.value.length,
      currentIndex: event.currentIndex,
    )) {
      return;
    }
    unawaited(_restartListLoopAtBeginning());
  }

  Future<void> _restartListLoopAtBeginning() async {
    _restartingListLoop = true;
    try {
      await _player.seek(Duration.zero, index: 0);
      await play();
    } catch (error, stackTrace) {
      _reportPlaybackError(error, stackTrace);
    } finally {
      _restartingListLoop = false;
    }
  }

  @override
  Future<void> play() {
    // just_audio completes this Future when playback ends, not when it starts.
    // Keep command completion independent and surface later errors to the shell.
    unawaited(_player.play().catchError(_reportPlaybackError));
    // _player.play() flips `playing` synchronously. Broadcast here as a
    // defensive fallback in addition to playingStream so audio_service never
    // misses the false -> true transition that starts Android foreground mode.
    _broadcastState(_player.playbackEvent);
    return Future.value();
  }

  void _reportPlaybackError(Object error, StackTrace stackTrace) {
    // Native error strings may include authenticated stream URLs.
    AppLog.error('音乐播放失败（${error.runtimeType}）', null, stackTrace);
    if (!_errors.isClosed) _errors.add('播放失败，请检查文件权限、音频格式或网络连接。');
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _broadcastState(_player.playbackEvent);
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    final index = nextQueueIndex(_player.currentIndex, queue.value.length);
    if (index == null) return;
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> skipToPrevious() async {
    final index = previousQueueIndex(_player.currentIndex, queue.value.length);
    if (index == null) return;
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> skipToQueueItem(int index) => _player.seek(null, index: index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _player.setLoopMode(audioServiceRepeatToLoopMode(repeatMode));
    // Loop/shuffle changes update just_audio's sequence state, not its
    // playback event stream. Broadcast the new state so the UI updates
    // immediately after a tap.
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (_changingPlaybackMode) return;
    _changingPlaybackMode = true;
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    try {
      await _setShuffleEnabled(enabled);
      _broadcastState(_player.playbackEvent);
    } finally {
      _changingPlaybackMode = false;
    }
  }

  Future<void> setPlaybackMode(PlaybackMode mode) async {
    if (_changingPlaybackMode) return;
    _changingPlaybackMode = true;
    try {
      final settings = playbackModeToAudioSettings(mode);
      await _setShuffleEnabled(settings.shuffleEnabled);
      await _player.setLoopMode(settings.loopMode);
      _broadcastState(_player.playbackEvent);
    } finally {
      _changingPlaybackMode = false;
    }
  }

  Future<void> _setShuffleEnabled(bool enabled) async {
    if (_tracks.isEmpty || enabled == _shuffleEnabled) {
      await _player.setShuffleModeEnabled(false);
      return;
    }
    if (enabled) {
      final current = _currentBaseIndex();
      await _rebuildQueue(buildShuffleOrder(_baseOrder, current, _random));
    } else {
      await _rebuildQueue(_baseOrder);
    }
    _shuffleEnabled = enabled;
  }

  int? _currentBaseIndex() {
    final currentId = mediaItem.value?.id;
    if (currentId != null) {
      final itemIndex = _items.indexWhere((item) => item.id == currentId);
      if (itemIndex >= 0) return itemIndex;
    }
    final activeIndex = _player.currentIndex;
    if (activeIndex == null ||
        activeIndex < 0 ||
        activeIndex >= _activeOrder.length) {
      return null;
    }
    return _activeOrder[activeIndex];
  }

  Future<void> _rebuildQueue(List<int> order) async {
    if (_tracks.isEmpty || order.isEmpty) return;
    final currentBaseIndex = _currentBaseIndex();
    final currentPosition = _player.position;
    final wasPlaying = _player.playing;
    final initialIndex = rebuildInitialIndex(order, currentBaseIndex);
    final sources = await Future.wait(
      order.map((index) => createAudioSource(_tracks[index], _items[index])),
    );

    _rebuildingQueue = true;
    try {
      await _player.setAudioSources(
        sources,
        initialIndex: initialIndex,
        initialPosition: currentPosition,
      );
      _activeOrder = List<int>.unmodifiable(order);
      queue.add([for (final index in order) _items[index]]);
    } finally {
      _rebuildingQueue = false;
    }
    _updateCurrentItem(initialIndex);
    // Shuffle order is represented by the reordered app playlist. Keeping the
    // native backend in sequential mode prevents MPV and just_audio from
    // maintaining two different notions of the current index.
    await _player.setShuffleModeEnabled(false);
    if (wasPlaying) await play();
  }

  Future<void> setVolume(double volume) async {
    final snapshot = resolveVolumeChange(
      requested: volume,
      volumeBeforeMute: _volumeBeforeMute,
    );
    _volumeBeforeMute = snapshot.volumeBeforeMute;
    _muted = snapshot.muted;
    await _player.setVolume(snapshot.applied);
  }

  Future<void> toggleMute() async {
    final snapshot = resolveMuteToggle(
      muted: _muted,
      currentVolume: _player.volume,
      volumeBeforeMute: _volumeBeforeMute,
    );
    _volumeBeforeMute = snapshot.volumeBeforeMute;
    _muted = snapshot.muted;
    await _player.setVolume(snapshot.applied);
  }

  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> gains,
    double preampDb = 0.0,
    String? presetId,
  }) => _equalizer.apply(
    enabled: enabled,
    gains: gains,
    preampDb: preampDb,
    presetId: presetId,
  );

  Future<void> setEqualizerPreset(String presetId) =>
      _equalizer.applyPreset(presetId);

  Future<void> disposePlayer() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _errors.close();
  }
}
