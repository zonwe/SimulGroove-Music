/// 自动检查更新开关（默认开启）。
///
/// 沿用旧版“启动时检查更新”的设置键，避免升级后丢失用户已经关闭的选择。
const updateAutoCheckSettingKey = 'update.check_on_startup';

/// 自动下载更新开关（默认关闭）。
///
/// 开启后启动检查发现新版本会在后台下载；安装前仍会请求确认。
const updateAutoDownloadSettingKey = 'update.auto_download';

/// 最近一次检查更新时间，用于限制启动检查频率。
const updateLastCheckAtSettingKey = 'update.last_check_at';

/// 用户选择“跳过此版本”的版本号。
const updateSkippedVersionSettingKey = 'update.skipped_version';

/// 启动自动检查的最小间隔，避免频繁重启时反复请求更新源。
///
/// 一天一次足够发现新版本，也避免每次启动都访问 GitHub。
const updateAutoCheckInterval = Duration(hours: 24);

bool updateAutoCheckFromSettings(Map<String, String> settings) =>
    settings[updateAutoCheckSettingKey] != 'false';

bool updateAutoDownloadFromSettings(Map<String, String> settings) =>
    settings[updateAutoDownloadSettingKey] == 'true';

DateTime? lastUpdateCheckFromSettings(Map<String, String> settings) =>
    DateTime.tryParse(settings[updateLastCheckAtSettingKey] ?? '')?.toLocal();

/// 是否应该执行启动自动更新检查。
bool shouldAutoCheckUpdates({
  required bool enabled,
  required DateTime? lastCheckedAt,
  DateTime? now,
}) {
  if (!enabled) return false;
  if (lastCheckedAt == null) return true;
  final current = now ?? DateTime.now();
  return current.difference(lastCheckedAt) >= updateAutoCheckInterval;
}

/// 是否在后台自动下载更新包。
///
/// 仅控制“下载”；是否安装仍由用户确认。默认关闭，只有用户在设置中显式开启
/// 后才后台下载。解压版没有卸载器，无法在应用内替换自身，也不自动下载。
bool shouldAutoDownloadUpdate({
  required bool autoDownloadEnabled,
  required bool installed,
  required bool updateAvailable,
}) => autoDownloadEnabled && installed && updateAvailable;
