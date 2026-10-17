import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

class FakeAudioPlayer extends Fake implements AudioPlayer {
  Completer<void>? playback;
  final events = StreamController<PlaybackEvent>.broadcast();
  List<AudioSource> sources = [];
  int playCalls = 0;

  @override
  bool playing = false;
  @override
  int? currentIndex;
  @override
  Duration position = Duration.zero;
  @override
  LoopMode loopMode = LoopMode.off;
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  double get speed => 1;
  @override
  PlaybackEvent get playbackEvent => PlaybackEvent(
    processingState: processingState,
    currentIndex: currentIndex,
    updatePosition: position,
  );
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    sources = audioSources;
    currentIndex = initialIndex;
    position = initialPosition ?? Duration.zero;
    return const Duration(minutes: 3);
  }

  @override
  Future<void> play() {
    playCalls++;
    if (playing) return Future.value();
    playing = true;
    playback = Completer<void>();
    return playback!.future;
  }

  @override
  Future<void> pause() async {
    playing = false;
    if (playback?.isCompleted == false) playback!.complete();
  }

  @override
  Future<void> stop() => pause();
  @override
  Future<void> setLoopMode(LoopMode mode) async {
    loopMode = mode;
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}
  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (position != null) this.position = position;
    if (index != null) currentIndex = index;
  }

  @override
  Future<void> dispose() async {
    await pause();
    await events.close();
  }
}
