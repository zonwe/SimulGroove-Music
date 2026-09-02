import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as ja;

/// 与音频插件调用解耦的队列顺序与播放模式纯函数。
///
/// 抽出这些逻辑便于编写无插件依赖的单元测试，
/// `MusicAudioHandler` 则专注于 audio_service 生命周期与 just_audio 调用。

/// 应用内播放模式：列表循环、单曲循环、列表随机。
enum PlaybackMode { listLoop, singleLoop, listShuffle }

/// 播放模式对应的底层音频设置：是否乱序重建队列 + just_audio 循环模式。
typedef PlaybackAudioSettings = ({bool shuffleEnabled, ja.LoopMode loopMode});

PlaybackAudioSettings playbackModeToAudioSettings(
  PlaybackMode mode,
) => switch (mode) {
  PlaybackMode.listLoop => (shuffleEnabled: false, loopMode: ja.LoopMode.all),
  PlaybackMode.singleLoop => (shuffleEnabled: false, loopMode: ja.LoopMode.one),
  PlaybackMode.listShuffle => (shuffleEnabled: true, loopMode: ja.LoopMode.all),
};

/// 系统媒体键的重复模式到 just_audio 循环模式的映射。
ja.LoopMode audioServiceRepeatToLoopMode(AudioServiceRepeatMode repeatMode) =>
    switch (repeatMode) {
      AudioServiceRepeatMode.one => ja.LoopMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => ja.LoopMode.all,
      _ => ja.LoopMode.off,
    };

/// 随机播放时重建的队列顺序：当前曲目保持在首位，其余乱序。
List<int> buildShuffleOrder(
  List<int> baseOrder,
  int? currentBaseIndex,
  Random random,
) {
  final remaining = List<int>.of(baseOrder)
    ..removeWhere((index) => index == currentBaseIndex)
    ..shuffle(random);
  final order = <int>[];
  if (currentBaseIndex != null) order.add(currentBaseIndex);
  order.addAll(remaining);
  return order;
}

/// 队列重建后应停留的初始索引；找不到当前曲目或队列为空时从头开始。
int rebuildInitialIndex(List<int> order, int? currentBaseIndex) {
  if (currentBaseIndex == null || order.isEmpty) return 0;
  final requested = order.indexOf(currentBaseIndex);
  if (requested < 0) return 0;
  return requested.clamp(0, order.length - 1);
}

/// 下一曲索引；空队列返回 null。
int? nextQueueIndex(int? current, int length) =>
    length == 0 ? null : ((current ?? -1) + 1) % length;

/// 上一曲索引；空队列返回 null。
int? previousQueueIndex(int? current, int length) =>
    length == 0 ? null : ((current ?? 0) - 1 + length) % length;

/// 列表循环播完最后一首后是否需要显式回到开头。
///
/// 某些平台后端在 LoopMode.all 下仍会把最后一首标记为 completed，
/// 不纠正会让播放器停在队列末尾。
bool shouldRestartListLoop({
  required ja.ProcessingState processingState,
  required ja.LoopMode loopMode,
  required bool rebuildingQueue,
  required bool restartingListLoop,
  required int queueLength,
  required int? currentIndex,
}) {
  if (processingState != ja.ProcessingState.completed ||
      loopMode != ja.LoopMode.all ||
      rebuildingQueue ||
      restartingListLoop) {
    return false;
  }
  return queueLength > 0 && currentIndex == queueLength - 1;
}

/// 均衡器增益不足 10 段时补零，与 10 段 UI 模型对齐；超出部分保持原样。
List<double> normalizeEqualizerGains(List<double> gains) {
  final normalized = List<double>.from(gains);
  if (normalized.length < 10) {
    normalized.addAll(List<double>.filled(10 - normalized.length, 0.0));
  }
  return normalized;
}

/// 把实际均衡器频段序号映射到增益数组下标（增益数组长度可能与频段数不同）。
int equalizerBandGainIndex({
  required int bandIndex,
  required int bandCount,
  required int gainCount,
}) {
  final normalizedIndex = bandCount == 1
      ? 0
      : (bandIndex / (bandCount - 1) * (gainCount - 1)).round();
  return normalizedIndex.clamp(0, gainCount - 1);
}
