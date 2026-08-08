import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../database/app_database.dart';
import 'artwork_cache.dart';
import 'local_audio_source.dart';

enum PlaybackMode { listLoop, singleLoop, listShuffle }

class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MusicAudioHandler() {
    _subscriptions.add(
      _player.playbackEventStream.listen(_handlePlaybackEvent),
    );
    _subscriptions.add(_player.currentIndexStream.listen(_updateCurrentItem));
  }

  final ja.AudioPlayer _player = ja.AudioPlayer();
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

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<ja.PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<double> get volumeStream => _player.volumeStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  Future<void> playTracks(List<Track> tracks, {int initialIndex = 0}) async {
    final items = await Future.wait(tracks.map(_toMediaItem));
    final sources = await Future.wait(
      List.generate(
        tracks.length,
        (index) => createAudioSource(tracks[index], items[index]),
      ),
    );
    _rebuildingQueue = true;
    try {
      await _player.setAudioSources(
        sources,
        initialIndex: initialIndex,
        initialPosition: Duration.zero,
      );
    } finally {
      _rebuildingQueue = false;
    }
    _tracks = List<Track>.unmodifiable(tracks);
    _items = List<MediaItem>.unmodifiable(items);
    _baseOrder = List<int>.generate(tracks.length, (index) => index);
    _activeOrder = List<int>.of(_baseOrder);
    _shuffleEnabled = false;
    queue.add(items);
    _updateCurrentItem(initialIndex);
    await play();
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
    final artUri = await cacheArtwork(id, artwork);
    final item = MediaItem(
      id: 'online:$id',
      title: title,
      artist: artist.isEmpty ? '未知艺术家' : artist,
      album: album,
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
      artUri: artUri,
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
      _rebuildingQueue = false;
    }
    _tracks = const [];
    _items = [item];
    _baseOrder = const [0];
    _activeOrder = const [0];
    _shuffleEnabled = false;
    queue.add([item]);
    _updateCurrentItem(0);
    await play();
  }

  Future<MediaItem> _toMediaItem(Track track) async {
    final artUri = await cacheArtwork(track.id, track.artwork);
    return MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.durationMs == null
          ? null
          : Duration(milliseconds: track.durationMs!),
      artUri: artUri,
      extras: {
        'uri': track.uri,
        'lyrics': track.lyrics,
        'sourceType': track.sourceType,
        'artwork': track.artwork,
      },
    );
  }

  void _updateCurrentItem(int? index) {
    if (_rebuildingQueue) return;
    final items = queue.value;
    if (index != null && index >= 0 && index < items.length) {
      mediaItem.add(items[index]);
    }
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
        queueIndex: event.currentIndex,
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

    // Some platform backends report the final item as completed even when
    // LoopMode.all is enabled. Explicitly seek to the first item so a list
    // loop never leaves the player stopped at the end of the queue.
    if (event.processingState != ja.ProcessingState.completed ||
        _player.loopMode != ja.LoopMode.all ||
        _rebuildingQueue ||
        _restartingListLoop) {
      return;
    }
    final length = queue.value.length;
    if (length == 0 || event.currentIndex != length - 1) return;
    unawaited(_restartListLoopAtBeginning());
  }

  Future<void> _restartListLoopAtBeginning() async {
    _restartingListLoop = true;
    try {
      await _player.seek(Duration.zero, index: 0);
      await _player.play();
    } finally {
      _restartingListLoop = false;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    final length = queue.value.length;
    if (length == 0) return;
    final current = _player.currentIndex ?? -1;
    final index = (current + 1) % length;
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> skipToPrevious() async {
    final length = queue.value.length;
    if (length == 0) return;
    final current = _player.currentIndex ?? 0;
    final index = (current - 1 + length) % length;
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> skipToQueueItem(int index) => _player.seek(null, index: index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => ja.LoopMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => ja.LoopMode.all,
      _ => ja.LoopMode.off,
    });
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
      switch (mode) {
        case PlaybackMode.listLoop:
          await _setShuffleEnabled(false);
          await _player.setLoopMode(ja.LoopMode.all);
        case PlaybackMode.singleLoop:
          await _setShuffleEnabled(false);
          await _player.setLoopMode(ja.LoopMode.one);
        case PlaybackMode.listShuffle:
          await _setShuffleEnabled(true);
          await _player.setLoopMode(ja.LoopMode.all);
      }
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
      final remaining = List<int>.of(_baseOrder)
        ..removeWhere((index) => index == current)
        ..shuffle(_random);
      final order = <int>[];
      if (current != null) order.add(current);
      order.addAll(remaining);
      await _rebuildQueue(order);
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
    final requestedIndex = currentBaseIndex == null
        ? 0
        : order.indexOf(currentBaseIndex);
    final initialIndex = requestedIndex < 0
        ? 0
        : requestedIndex.clamp(0, order.length - 1);
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
    if (wasPlaying) await _player.play();
  }

  Future<void> setVolume(double volume) async {
    final next = volume.clamp(0.0, 1.0).toDouble();
    if (next > 0) {
      _volumeBeforeMute = next;
      _muted = false;
    } else {
      _muted = true;
    }
    await _player.setVolume(next);
  }

  Future<void> toggleMute() async {
    if (_muted || _player.volume <= 0) {
      _muted = false;
      final restored = _volumeBeforeMute.clamp(0.05, 1.0).toDouble();
      await _player.setVolume(restored);
      return;
    }
    _volumeBeforeMute = _player.volume;
    _muted = true;
    await _player.setVolume(0);
  }

  Future<void> setEqualizerPreset(String preset) async {
    // The shared just_audio backend does not expose band-level DSP on every
    // target. Presets currently apply a safe preamp while keeping the setting
    // ready for platform-specific band effects later.
    final gain = switch (preset) {
      'bass' => 1.0,
      'vocal' => 0.96,
      'classical' => 0.98,
      _ => 1.0,
    };
    await _player.setVolume(gain);
  }

  Future<void> disposePlayer() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
  }
}
