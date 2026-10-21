import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/update/app_version.dart';
import '../../core/update/update_service.dart';
import '../../core/update/update_settings.dart';
import '../update/update_dialog.dart';
import 'settings_section.dart';

/// 应用更新设置：版本展示、启动检查和手动检查。
///
/// Windows 安装版支持静默升级；Android 下载 APK 后交给系统安装界面。
class UpdateSettingsSection extends ConsumerStatefulWidget {
  const UpdateSettingsSection({super.key});

  @override
  ConsumerState<UpdateSettingsSection> createState() =>
      _UpdateSettingsSectionState();
}

class _UpdateSettingsSectionState extends ConsumerState<UpdateSettingsSection> {
  AppVersion? _version;
  DateTime? _lastChecked;
  bool _installed = false;
  bool _loading = true;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final service = ref.read(appUpdateServiceProvider);
    try {
      final version = await service.currentVersion();
      final lastText = await ref
          .read(databaseProvider)
          .readSetting(updateLastCheckAtSettingKey);
      if (!mounted) return;
      setState(() {
        _version = version;
        _lastChecked = DateTime.tryParse(lastText ?? '')?.toLocal();
        _installed = service.isInstalled;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _checkForUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    final service = ref.read(appUpdateServiceProvider);
    final database = ref.read(databaseProvider);
    try {
      final result = await service.checkForUpdates();
      final checkedAt = DateTime.now();
      await database.setSetting(
        updateLastCheckAtSettingKey,
        checkedAt.toUtc().toIso8601String(),
      );
      if (!mounted) return;
      setState(() => _lastChecked = checkedAt);
      switch (result) {
        case UpdateUnsupported(:final reason):
          _showMessage(reason);
        case UpdateUpToDate(:final current):
          _showMessage('已是最新版本 ${current.display}');
        case final UpdateAvailable available:
          await showUpdateAvailableDialog(
            context,
            update: available,
            allowSkip: false,
          );
      }
    } on UpdateException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage('检查更新失败：$error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final autoCheck = ref.watch(updateCheckOnStartupProvider).value ?? true;
    final service = ref.watch(appUpdateServiceProvider);
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final versionLabel = _loading
        ? '正在读取版本…'
        : '当前版本 ${_version?.display ?? '未知'} · ${service.platformLabel}';
    return SettingsSection(
      title: '应用更新',
      children: [
        ListTile(
          leading: const Icon(Icons.system_update_outlined),
          title: const Text('SimulGroove Music'),
          subtitle: Text(versionLabel),
        ),
        const Divider(height: 1),
        SwitchListTile(
          secondary: const Icon(Icons.update_outlined),
          title: const Text('启动时检查更新'),
          subtitle: const Text('最多每 12 小时检查一次；发现新版本时提示，不自动下载'),
          value: autoCheck,
          onChanged: (value) => ref
              .read(databaseProvider)
              .setSetting(updateCheckOnStartupSettingKey, '$value'),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.cloud_download_outlined),
          title: const Text('检查更新'),
          subtitle: Text(
            _lastChecked == null
                ? '尚未检查'
                : '上次检查：${formatUpdateDateTime(_lastChecked!)}',
          ),
          trailing: _checking
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.tonal(
                  onPressed: _loading ? null : _checkForUpdates,
                  child: const Text('检查'),
                ),
        ),
        if (!_loading && isWindows && !_installed) ...[
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('当前为解压版'),
            subtitle: Text('应用内自动安装需要 Windows 安装版；检查到新版本时可复制安装包链接手动安装。'),
          ),
        ],
      ],
    );
  }
}

String formatUpdateDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
