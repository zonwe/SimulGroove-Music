import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/log/app_log.dart';
import '../../core/update/update_service.dart';
import '../../core/update/update_settings.dart';
import 'update_dialog.dart';

/// 应用启动后的更新检查入口。
///
/// 自动检查只负责提示，不自动下载；用户确认后才进入校验与静默安装流程。
class StartupUpdateGate extends ConsumerStatefulWidget {
  const StartupUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StartupUpdateGate> createState() => _StartupUpdateGateState();
}

class _StartupUpdateGateState extends ConsumerState<StartupUpdateGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    await _reportPendingFailure();
    await _checkForUpdates();
  }

  Future<void> _reportPendingFailure() async {
    final service = ref.read(appUpdateServiceProvider);
    if (!service.isSupported) return;
    try {
      final failure = await service.takePendingFailure();
      if (failure == null || !mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('上次自动更新没有完成：$failure'),
            duration: const Duration(seconds: 10),
          ),
        );
    } catch (error, stackTrace) {
      AppLog.warning('读取上次更新失败标记失败', error, stackTrace);
    }
  }

  Future<void> _checkForUpdates() async {
    final service = ref.read(appUpdateServiceProvider);
    if (!service.isSupported) return;
    final database = ref.read(databaseProvider);
    try {
      // 等待首帧稳定后再访问网络与弹窗，避免启动阶段的窗口动画被阻塞。
      await Future<void>.delayed(const Duration(seconds: 2));
      final enabled =
          await database.readSetting(updateCheckOnStartupSettingKey) != 'false';
      final lastText = await database.readSetting(updateLastCheckAtSettingKey);
      final lastChecked = DateTime.tryParse(lastText ?? '')?.toLocal();
      if (!shouldAutoCheckUpdates(
        enabled: enabled,
        lastCheckedAt: lastChecked,
      )) {
        return;
      }
      final skipped = await database.readSetting(
        updateSkippedVersionSettingKey,
      );

      final result = await service.checkForUpdates();
      await database.setSetting(
        updateLastCheckAtSettingKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      if (!mounted || result is! UpdateAvailable) return;
      if (skipped == result.release.version.canonical) return;
      await showUpdateAvailableDialog(context, update: result, allowSkip: true);
    } on UpdateException catch (error) {
      // 启动检查失败不应打扰正常使用，设置页的手动检查会给出具体原因。
      AppLog.warning('启动检查更新失败', error);
    } catch (error, stackTrace) {
      AppLog.warning('启动检查更新失败', error, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
