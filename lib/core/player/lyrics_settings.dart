/// 歌词点击定位设置：在正在播放页点按歌词行时跳转到该句开始时间。
const lyricsTapToSeekSettingKey = 'player.lyrics.tap_to_seek';
const lyricsTapToSeekConfirmSettingKey = 'player.lyrics.tap_to_seek.confirm';

/// 默认开启点击定位；旧数据库没有该设置时也保持可用。
const lyricsTapToSeekEnabledByDefault = true;

/// 默认不弹确认，保证“快速定位”不被每一次点按打断。
const lyricsTapToSeekConfirmByDefault = false;

bool lyricsTapToSeekEnabledFromSettings(Map<String, String> settings) =>
    settings[lyricsTapToSeekSettingKey] != 'false';

bool lyricsTapToSeekConfirmFromSettings(Map<String, String> settings) =>
    settings[lyricsTapToSeekConfirmSettingKey] == 'true';
