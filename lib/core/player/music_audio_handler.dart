import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../database/app_database.dart';
import 'artwork_cache.dart';

class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MusicAudioHandler() {
    _subscriptions.add(_player.playbackEventStream.listen(_broadcastState));
    _subscriptions.add(_player.currentIndexStream.listen(_updateCurrentItem));
  }

  final ja.AudioPlayer _player = ja.AudioPlayer();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<ja.PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<double> get volumeStream => _player.volumeStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  Future<void> playTracks(List<Track> tracks, {int initialIndex = 0}) async {
    final items = await Future.wait(tracks.map(_toMediaItem));
    queue.add(items);
    await _player.setAudioSources(
      items
          .map(
            (item) => ja.AudioSource.uri(
              Uri.parse(item.extras!['uri']! as String),
              tag: item,
            ),
          )
          .toList(growable: false),
      initialIndex: initialIndex,
      initialPosition: Duration.zero,
    );
    _updateCurrentItem(initialIndex);
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
        shuffleMode: _player.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
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
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) =>
      _player.seek(Duration.zero, index: index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => ja.LoopMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => ja.LoopMode.all,
      _ => ja.LoopMode.off,
    });
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
  }

  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0, 1));

  Future<void> disposePlayer() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
  }
}
