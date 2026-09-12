import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/library/library_scan_controller.dart';

class LibraryScanSettingsSection extends ConsumerStatefulWidget {
  const LibraryScanSettingsSection({super.key});

  @override
  ConsumerState<LibraryScanSettingsSection> createState() =>
      _LibraryScanSettingsSectionState();
}

class _LibraryScanSettingsSectionState
    extends ConsumerState<LibraryScanSettingsSection> {
  @override
  Widget build(BuildContext context) {
    final scanner = ref.watch(scannerProvider);
    if (!scanner.isSupported) return const SizedBox.shrink();
    final sources = ref.watch(scanSourcesProvider);
    final notificationEnabled =
        ref.watch(scanNotificationEnabledProvider).value ?? true;
    final colors = Theme.of(context).colorScheme;
    final controller = ref.watch(libraryScanControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Text(
                '音乐库搜索位置',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: controller.busy
                        ? null
                        : () => unawaited(controller.scan()),
                    icon: controller.operation == LibraryScanOperation.scan
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.create_new_folder_outlined),
                    label: Text(
                      controller.operation == LibraryScanOperation.scan
                          ? '扫描中…'
                          : scanner.actionLabel,
                    ),
                  ),
                  if (scanner.supportsFullDeviceScan)
                    OutlinedButton.icon(
                      onPressed: controller.busy
                          ? null
                          : () => unawaited(controller.scan(fullDevice: true)),
                      icon: const Icon(Icons.phone_android_outlined),
                      label: const Text('扫描整台设备'),
                    ),
                  OutlinedButton.icon(
                    onPressed: controller.busy
                        ? null
                        : () => unawaited(controller.rescanAll()),
                    icon: controller.operation == LibraryScanOperation.rescan
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(
                      controller.operation == LibraryScanOperation.rescan
                          ? '重新扫描中…'
                          : '重新扫描全部',
                    ),
                  ),
                ],
              ),
            ),
            if (controller.message case final message?)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  message,
                  style: TextStyle(
                    color: controller.hasError
                        ? colors.error
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              value: notificationEnabled,
              title: const Text('扫描通知'),
              subtitle: const Text('音乐库扫描进行与完成时发送系统通知'),
              secondary: const Icon(Icons.notifications_none_outlined),
              onChanged: (value) async {
                await ref
                    .read(databaseProvider)
                    .setSetting(
                      scanNotificationEnabledSettingKey,
                      value.toString(),
                    );
              },
            ),
            const Divider(height: 1),
            sources.when(
              loading: () => const LinearProgressIndicator(minHeight: 2),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '搜索位置读取失败：$error',
                  style: TextStyle(color: colors.error),
                ),
              ),
              data: (values) {
                if (values.isEmpty) {
                  return const ListTile(
                    leading: Icon(Icons.folder_off_outlined),
                    title: Text('尚未指定搜索位置'),
                    subtitle: Text('添加音乐文件夹后，应用会把其中的音频导入音乐库。'),
                  );
                }
                return Column(
                  children: [
                    for (var index = 0; index < values.length; index++) ...[
                      if (index > 0) const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(values[index].label),
                        subtitle: Text(
                          _sourceLocation(values[index]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: '删除搜索位置',
                          onPressed: controller.busy
                              ? null
                              : () => unawaited(_deleteSource(values[index])),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSource(ScanSource source) async {
    final controller = ref.read(libraryScanControllerProvider);
    if (controller.busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除搜索位置？'),
        content: Text('将移除“${source.label}”以及该位置导入的歌曲。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await controller.deleteSource(source);
  }
}

String _sourceLocation(ScanSource source) {
  if (source.uri == 'media-store://external') {
    return 'Android MediaStore · 整台设备';
  }
  if (source.uri.startsWith('content://')) return 'Android 已授权目录';
  return source.uri;
}
