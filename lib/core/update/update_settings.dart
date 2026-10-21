/// 启动时自动检查更新（默认开启）。
const updateCheckOnStartupSettingKey = 'update.check_on_startup';

/// 最近一次检查更新时间，用于限制启动检查频率。
const updateLastCheckAtSettingKey = 'update.last_check_at';

/// 用户选择“跳过此版本”的版本号。
const updateSkippedVersionSettingKey = 'update.skipped_version';

/// 启动自动检查的最小间隔，避免频繁重启时反复请求更新源。
const updateAutoCheckInterval = Duration(hours: 12);

bool updateCheckOnStartupFromSettings(Map<String, String> settings) =>
    settings[updateCheckOnStartupSettingKey] != 'false';

DateTime? lastUpdateCheckFromSettings(Map<String, String> settings) =>
    DateTime.tryParse(settings[updateLastCheckAtSettingKey] ?? '')?.toLocal();

/// 是否应该执行启动自动检查。
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
