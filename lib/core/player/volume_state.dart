/// 音量与静音的纯状态机。
///
/// 从 `MusicAudioHandler` 拆出，便于无插件单元测试；
/// handler 负责把返回的 `applied` 值写入真实播放器。
library;

/// 一次音量操作后的状态快照。
typedef VolumeSnapshot = ({
  double applied,
  double volumeBeforeMute,
  bool muted,
});

/// 处理显式设置音量：大于 0 的音量会同时解除静音并记住为新基准。
VolumeSnapshot resolveVolumeChange({
  required double requested,
  required double volumeBeforeMute,
}) {
  final clamped = requested.clamp(0.0, 1.0).toDouble();
  if (clamped > 0) {
    return (applied: clamped, volumeBeforeMute: clamped, muted: false);
  }
  return (applied: 0, volumeBeforeMute: volumeBeforeMute, muted: true);
}

/// 处理静音切换：静音中或音量已为 0 时恢复到基准音量，否则记录基准并静音。
VolumeSnapshot resolveMuteToggle({
  required bool muted,
  required double currentVolume,
  required double volumeBeforeMute,
}) {
  if (muted || currentVolume <= 0) {
    return (
      applied: volumeBeforeMute.clamp(0.05, 1.0).toDouble(),
      volumeBeforeMute: volumeBeforeMute,
      muted: false,
    );
  }
  return (applied: 0, volumeBeforeMute: currentVolume, muted: true);
}
