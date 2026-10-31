// 播放时长展示格式化。
//
// 只放无副作用的纯函数：音乐库、收藏、歌单和播放器共用同一份实现，
// 避免每个页面各写一遍 `padLeft(2, '0')` 之后出现格式漂移。

/// 把时长格式化为 `m:ss`。
///
/// 分钟数不截断到 60 以内：超过一小时的曲目显示 `72:30` 而不是 `12:30`。
String formatPlaybackDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// 毫秒版本；时长未知时显示 `--:--`。
String formatTrackDuration(int? milliseconds) => milliseconds == null
    ? '--:--'
    : formatPlaybackDuration(Duration(milliseconds: milliseconds));
