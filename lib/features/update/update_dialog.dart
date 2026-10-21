import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/update/update_manifest.dart';
import '../../core/update/update_service.dart';
import '../../core/update/update_settings.dart';
import '../../core/window/desktop_window_controller.dart';

/// 展示“发现新版本”对话框。自动检查与设置页手动检查共用同一套流程。
Future<void> showUpdateAvailableDialog(
  BuildContext context, {
  required UpdateAvailable update,
  required bool allowSkip,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateAvailableDialog(update: update, allowSkip: allowSkip),
  );
}

class UpdateAvailableDialog extends ConsumerStatefulWidget {
  const UpdateAvailableDialog({
    super.key,
    required this.update,
    required this.allowSkip,
  });

  final UpdateAvailable update;

  /// 启动自动检查允许“跳过此版本”；手动检查不提供该选项。
  final bool allowSkip;

  @override
  ConsumerState<UpdateAvailableDialog> createState() =>
      _UpdateAvailableDialogState();
}

enum _UpdatePhase { idle, downloading, ready, launching, error }

class _UpdateAvailableDialogState extends ConsumerState<UpdateAvailableDialog> {
  _UpdatePhase _phase = _UpdatePhase.idle;
  double? _progress;
  int _received = 0;
  String? _installerPath;
  String? _error;
  bool _installed = false;

  UpdateRelease get _release => widget.update.release;
  UpdateAsset get _asset => widget.update.asset;

  @override
  void initState() {
    super.initState();
    _installed = ref.read(appUpdateServiceProvider).isInstalled;
  }

  Future<void> _download() async {
    setState(() {
      _phase = _UpdatePhase.downloading;
      _progress = 0;
      _received = 0;
      _error = null;
    });
    try {
      final path = await ref
          .read(appUpdateServiceProvider)
          .downloadUpdate(
            _asset,
            onProgress: (received, total) {
              if (!mounted) return;
              setState(() {
                _received = received;
                _progress = total == null || total <= 0
                    ? null
                    : received / total;
              });
            },
          );
      if (!mounted) return;
      setState(() {
        _installerPath = path;
        _phase = _UpdatePhase.ready;
      });
    } on UpdateException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _error = '下载更新失败：$error';
      });
    }
  }

  Future<void> _install() async {
    final path = _installerPath;
    if (path == null) return;
    setState(() {
      _phase = _UpdatePhase.launching;
      _error = null;
    });
    try {
      final service = ref.read(appUpdateServiceProvider);
      await service.launchInstaller(
        installerPath: path,
        targetVersion: _release.version,
      );
      if (service.requiresAppExit) {
        // Windows 安装助手会等待本进程退出；这里先走正常退出流程保存播放快照。
        await DesktopWindowController.quit();
        return;
      }
      // Android 由系统安装界面接管，不能主动退出应用。
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('已打开系统安装界面，请确认安装。')));
    } on UpdateException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _error = '无法启动安装程序：$error';
      });
    }
  }

  Future<void> _skipVersion() async {
    await ref
        .read(databaseProvider)
        .setSetting(updateSkippedVersionSettingKey, _release.version.canonical);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _copyDownloadLink() async {
    await Clipboard.setData(ClipboardData(text: _asset.uri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('安装包下载链接已复制。')));
  }

  void _retry() {
    if (_installerPath == null) {
      _download();
    } else {
      _install();
    }
  }

  bool get _canPop =>
      _phase != _UpdatePhase.downloading && _phase != _UpdatePhase.launching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = ref.watch(appUpdateServiceProvider);
    // 桌面弹窗保持固定宽度；Android 窄屏按可用宽度收缩，避免横向溢出。
    final contentWidth = (MediaQuery.sizeOf(context).width - 80)
        .clamp(240.0, 460.0)
        .toDouble();
    return PopScope(
      canPop: _canPop,
      child: AlertDialog(
        title: Text('发现新版本 ${_release.version.versionText}'),
        content: SizedBox(
          width: contentWidth,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '当前版本 ${widget.update.current.display} → 新版本 ${_release.version.display}',
                ),
                const SizedBox(height: 6),
                Text(
                  '安装包大小：${formatUpdateBytes(_asset.size)}',
                  style: theme.textTheme.bodySmall,
                ),
                if (_release.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('更新内容', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  SelectableText(
                    _release.notes,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                if (!_installed) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '当前是解压版，应用内自动安装不可用。请复制下载链接后手动安装；'
                      '安装版后续可以直接在应用内升级。',
                    ),
                  ),
                ],
                if (_phase == _UpdatePhase.downloading) ...[
                  const SizedBox(height: 20),
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text(
                    '${((_progress ?? 0) * 100).toStringAsFixed(0)}% · '
                    '${formatUpdateBytes(_received)} / ${formatUpdateBytes(_asset.size)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_phase == _UpdatePhase.ready) ...[
                  const SizedBox(height: 20),
                  Text(
                    '安装包已下载并通过 SHA-256 校验。${service.installHint}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                if (_phase == _UpdatePhase.error && _error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: _buildActions(),
      ),
    );
  }

  List<Widget> _buildActions() {
    final requiresAppExit = ref.read(appUpdateServiceProvider).requiresAppExit;
    switch (_phase) {
      case _UpdatePhase.idle:
        return [
          if (widget.allowSkip)
            TextButton(onPressed: _skipVersion, child: const Text('跳过此版本')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
          if (_installed)
            FilledButton(onPressed: _download, child: const Text('下载并安装'))
          else
            FilledButton(
              onPressed: _copyDownloadLink,
              child: const Text('复制下载链接'),
            ),
        ];
      case _UpdatePhase.downloading:
        return [const TextButton(onPressed: null, child: Text('正在下载并校验…'))];
      case _UpdatePhase.ready:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: _install,
            child: Text(requiresAppExit ? '立即安装并重启' : '打开系统安装界面'),
          ),
        ];
      case _UpdatePhase.launching:
        return [
          TextButton(
            onPressed: null,
            child: Text(requiresAppExit ? '正在退出…' : '正在打开安装界面…'),
          ),
        ];
      case _UpdatePhase.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: _retry,
            child: Text(_installerPath == null ? '重新下载' : '重试安装'),
          ),
        ];
    }
  }
}

String formatUpdateBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}
