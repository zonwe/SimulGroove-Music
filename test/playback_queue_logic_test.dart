import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_music/core/player/playback_queue_logic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;

void main() {
  group('playbackModeToAudioSettings', () {
    test('列表循环关闭乱序并循环整个列表', () {
      final settings = playbackModeToAudioSettings(PlaybackMode.listLoop);
      expect(settings.shuffleEnabled, isFalse);
      expect(settings.loopMode, ja.LoopMode.all);
    });

    test('单曲循环关闭乱序并只循环当前曲目', () {
      final settings = playbackModeToAudioSettings(PlaybackMode.singleLoop);
      expect(settings.shuffleEnabled, isFalse);
      expect(settings.loopMode, ja.LoopMode.one);
    });

    test('列表随机开启乱序并循环整个列表', () {
      final settings = playbackModeToAudioSettings(PlaybackMode.listShuffle);
      expect(settings.shuffleEnabled, isTrue);
      expect(settings.loopMode, ja.LoopMode.all);
    });
  });

  group('audioServiceRepeatToLoopMode', () {
    test('单曲、列表、分组与关闭的映射', () {
      expect(
        audioServiceRepeatToLoopMode(AudioServiceRepeatMode.one),
        ja.LoopMode.one,
      );
      expect(
        audioServiceRepeatToLoopMode(AudioServiceRepeatMode.all),
        ja.LoopMode.all,
      );
      expect(
        audioServiceRepeatToLoopMode(AudioServiceRepeatMode.group),
        ja.LoopMode.all,
      );
      expect(
        audioServiceRepeatToLoopMode(AudioServiceRepeatMode.none),
        ja.LoopMode.off,
      );
    });
  });

  group('buildShuffleOrder', () {
    test('当前曲目保持在首位，其余随机排列且不重复', () {
      final random = Random(42);
      final order = buildShuffleOrder([0, 1, 2, 3, 4], 2, random);

      expect(order.first, 2);
      expect(order.toSet().length, order.length, reason: '乱序不应重复或丢失曲目');
      expect(order.toSet(), {0, 1, 2, 3, 4});
    });

    test('无法确定当前曲目时全部乱序', () {
      final order = buildShuffleOrder([0, 1, 2], null, Random(7));

      expect(order.toSet(), {0, 1, 2});
    });

    test('单曲目队列保持原样', () {
      expect(buildShuffleOrder([0], 0, Random(1)), [0]);
    });
  });

  group('rebuildInitialIndex', () {
    test('当前曲目在新顺序中的位置作为初始索引', () {
      expect(rebuildInitialIndex([3, 1, 0, 2], 0), 2);
    });

    test('找不到当前曲目或队列为空时回到开头', () {
      expect(rebuildInitialIndex([1, 2], 0), 0);
      expect(rebuildInitialIndex([1, 2], null), 0);
      expect(rebuildInitialIndex([], 1), 0);
    });
  });

  group('nextQueueIndex / previousQueueIndex', () {
    test('越界时环绕', () {
      expect(nextQueueIndex(0, 3), 1);
      expect(nextQueueIndex(2, 3), 0);
      expect(previousQueueIndex(0, 3), 2);
      expect(previousQueueIndex(2, 3), 1);
    });

    test('无当前索引时下一曲从 0 开始、上一曲停在最后一首', () {
      expect(nextQueueIndex(null, 3), 0);
      expect(previousQueueIndex(null, 3), 2);
    });

    test('空队列返回 null', () {
      expect(nextQueueIndex(0, 0), isNull);
      expect(previousQueueIndex(0, 0), isNull);
    });
  });

  group('shouldRestartListLoop', () {
    test('仅在列表循环播完最后一首时重启', () {
      expect(
        shouldRestartListLoop(
          processingState: ja.ProcessingState.completed,
          loopMode: ja.LoopMode.all,
          rebuildingQueue: false,
          restartingListLoop: false,
          queueLength: 3,
          currentIndex: 2,
        ),
        isTrue,
      );
    });

    test('其他循环模式、非完成状态、队列边界外的索引都不重启', () {
      bool restart({
        ja.ProcessingState processingState = ja.ProcessingState.completed,
        ja.LoopMode loopMode = ja.LoopMode.all,
        int queueLength = 3,
        int? currentIndex = 2,
      }) => shouldRestartListLoop(
        processingState: processingState,
        loopMode: loopMode,
        rebuildingQueue: false,
        restartingListLoop: false,
        queueLength: queueLength,
        currentIndex: currentIndex,
      );

      expect(restart(loopMode: ja.LoopMode.one), isFalse);
      expect(restart(loopMode: ja.LoopMode.off), isFalse);
      expect(restart(processingState: ja.ProcessingState.ready), isFalse);
      expect(restart(currentIndex: 1), isFalse);
      expect(restart(currentIndex: null), isFalse);
      expect(restart(queueLength: 0, currentIndex: null), isFalse);
    });
  });

  group('normalizeEqualizerGains', () {
    test('不足 10 段时补零', () {
      expect(normalizeEqualizerGains([1, 2, 3]), [
        1,
        2,
        3,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(normalizeEqualizerGains([]), List<double>.filled(10, 0));
    });

    test('足量或超长时保持原值', () {
      final tenGains = List<double>.generate(10, (i) => i.toDouble());
      expect(normalizeEqualizerGains(tenGains), tenGains);
    });
  });

  group('equalizerBandGainIndex', () {
    test('频段数与增益段数一致时按下标对应', () {
      expect(
        equalizerBandGainIndex(bandIndex: 4, bandCount: 10, gainCount: 10),
        4,
      );
    });

    test('频段较少时按比例映射到 10 段', () {
      expect(
        equalizerBandGainIndex(bandIndex: 0, bandCount: 5, gainCount: 10),
        0,
      );
      expect(
        equalizerBandGainIndex(bandIndex: 4, bandCount: 5, gainCount: 10),
        9,
      );
      expect(
        equalizerBandGainIndex(bandIndex: 2, bandCount: 5, gainCount: 10),
        5,
      );
    });

    test('单频段固定使用第一段增益', () {
      expect(
        equalizerBandGainIndex(bandIndex: 0, bandCount: 1, gainCount: 10),
        0,
      );
    });
  });
}
