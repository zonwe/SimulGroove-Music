import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/log/app_log.dart';
import '../../core/update/update_service.dart';
import '../../core/update/update_settings.dart';
import 'update_dialog.dart';

/// 应用启动后的自动更新入口。
///
/// “自动检查更新”默认开启，启动时最多每 24 小时检查一次；“自动下载更新”默认
/// 关闭，只有显式开启后才在后台下载并校验。无论哪种模式，安装前都会请求确认。
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
            content: Text('上次应用更新没有完成：$failure'),
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
      final autoCheck =
          await database.readSetting(updateAutoCheckSettingKey) != 'false';
      final autoDownload =
          await database.readSetting(updateAutoDownloadSettingKey) == 'true';
      final lastText = await database.readSetting(updateLastCheckAtSettingKey);
      final lastChecked = DateTime.tryParse(lastText ?? '')?.toLocal();
      if (!shouldAutoCheckUpdates(
        enabled: autoCheck,
        lastCheckedAt: lastChecked,
      )) {
        return;
      }
      final skipped = await database.readSetting(
        updateSkippedVersionSettingKey,
      );

      // 先记录本次尝试时间：即使网络失败也等满 24 小时再自动重试，避免每次
      // 启动都访问 GitHub；用户仍可在设置页手动检查。
      await database.setSetting(
        updateLastCheckAtSettingKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      final result = await service.checkForUpdates();
      if (!mounted || result is! UpdateAvailable) return;
      if (skipped == result.release.version.canonical) return;

      String? installerPath;
      String? downloadError;
      if (shouldAutoDownloadUpdate(
        autoDownloadEnabled: autoDownload,
        installed: service.isInstalled,
        updateAvailable: true,
      )) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        final progress = messenger.showSnackBar(
          SnackBar(
            content: Text('正在后台下载更新 ${result.release.version.versionText}…'),
            duration: const Duration(minutes: 5),
          ),
        );
        try {
          installerPath = await service.downloadUpdate(result.asset);
        } on UpdateException catch (error) {
          downloadError = error.message;
          AppLog.warning('自动下载更新失败', error);
        } catch (error, stackTrace) {
          downloadError = '自动下载更新失败：$error';
          AppLog.warning('自动下载更新失败', error, stackTrace);
        }
        // 只关闭本次下载提示，避免误关用户刚触发的其他 SnackBar。
        if (mounted) progress.close();
      }
      if (!mounted) return;
      await showUpdateAvailableDialog(
        context,
        update: result,
        allowSkip: true,
        installerPath: installerPath,
        initialError: downloadError,
      );
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
