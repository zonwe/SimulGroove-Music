import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../core/player/music_audio_handler.dart';

/// 正在播放页的播放模式换算与展示描述，均为纯函数。

PlaybackMode playbackModeFromState(PlaybackState state) {
  if (state.shuffleMode != AudioServiceShuffleMode.none) {
    return PlaybackMode.listShuffle;
  }
  if (state.repeatMode == AudioServiceRepeatMode.one) {
    return PlaybackMode.singleLoop;
  }
  return PlaybackMode.listLoop;
}

PlaybackMode nextPlaybackMode(PlaybackMode mode) => switch (mode) {
  PlaybackMode.listLoop => PlaybackMode.singleLoop,
  PlaybackMode.singleLoop => PlaybackMode.listShuffle,
  PlaybackMode.listShuffle => PlaybackMode.listLoop,
};

String playbackModeLabel(PlaybackMode mode) => switch (mode) {
  PlaybackMode.listLoop => '列表循环，点击切换单曲循环',
  PlaybackMode.singleLoop => '单曲循环，点击切换列表随机',
  PlaybackMode.listShuffle => '列表随机，点击切换列表循环',
};

IconData playbackModeIcon(PlaybackMode mode) => switch (mode) {
  PlaybackMode.listLoop => Icons.repeat_rounded,
  PlaybackMode.singleLoop => Icons.repeat_one_rounded,
  PlaybackMode.listShuffle => Icons.shuffle_rounded,
};
