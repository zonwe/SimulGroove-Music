import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/library/scanned_track.dart';

class LibraryScanSettingsSection extends ConsumerStatefulWidget {
  const LibraryScanSettingsSection({super.key});

  @override
  ConsumerState<LibraryScanSettingsSection> createState() =>
      _LibraryScanSettingsSectionState();
}

class _LibraryScanSettingsSectionState
    extends ConsumerState<LibraryScanSettingsSection> {
  bool _scanning = false;
  bool _rescanAllBusy = false;

  @override
  Widget build(BuildContext context) {
    final scanner = ref.watch(scannerProvider);
    if (!scanner.isSupported) return const SizedBox.shrink();
    final sources = ref.watch(scanSourcesProvider);
    final colors = Theme.of(context).colorScheme;
    return Card(
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _scanning ? null : () => unawaited(_scan()),
                  icon: _scanning
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.create_new_folder_outlined),
                  label: Text(_scanning ? '扫描中…' : scanner.actionLabel),
                ),
                if (scanner.supportsFullDeviceScan)
                  OutlinedButton.icon(
                    onPressed: _scanning
                        ? null
                        : () => unawaited(_scan(fullDevice: true)),
                    icon: const Icon(Icons.phone_android_outlined),
                    label: const Text('扫描整台设备'),
                  ),
                OutlinedButton.icon(
                  onPressed: _rescanAllBusy
                      ? null
                      : () => unawaited(_rescanAll()),
                  icon: _rescanAllBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_rescanAllBusy ? '重新扫描中…' : '重新扫描全部'),
                ),
              ],
            ),
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
                        onPressed: () =>
                            unawaited(_deleteSource(values[index])),
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
    );
  }

  Future<void> _rescanAll() async {
    if (_rescanAllBusy) return;
    final sources = await ref.read(databaseProvider).watchScanSources().first;
    if (sources.isEmpty) {
      _showMessage('还没有添加搜索位置');
      return;
    }
    setState(() => _rescanAllBusy = true);
    var imported = 0;
    try {
      final scanner = ref.read(scannerProvider);
      final database = ref.read(databaseProvider);
      for (final source in sources) {
        final result = await scanner.rescanSource(
          sourceUri: source.uri,
          platform: source.platform,
          sourceLabel: source.label,
        );
        if (result == null) continue;
        imported += result.tracks.length;
        await database.replaceScanSourceTracks(
          source,
          result.tracks.map(_toCompanion),
        );
        await database.saveScanSource(
          ScanSourcesCompanion.insert(
            id: source.id,
            platform: result.tracks.firstOrNull?.sourceType ?? source.platform,
            uri: result.sourceUri,
            label: result.sourceLabel,
            lastScannedAt: Value(DateTime.now()),
          ),
        );
      }
      if (mounted) {
        _showMessage('已重新扫描 ${sources.length} 个位置，更新 $imported 首歌曲');
      }
    } catch (error) {
      if (mounted) _showMessage('重新扫描失败：$error');
    } finally {
      if (mounted) setState(() => _rescanAllBusy = false);
    }
  }

  Future<void> _deleteSource(ScanSource source) async {
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
    if (confirmed != true) return;
    await ref.read(databaseProvider).deleteScanSource(source);
    if (mounted) _showMessage('已删除搜索位置“${source.label}”并更新音乐库');
  }

  Future<void> _scan({bool fullDevice = false}) async {
    setState(() => _scanning = true);
    try {
      final scanner = ref.read(scannerProvider);
      final result = fullDevice
          ? await scanner.scanFullDevice()
          : await scanner.scan();
      if (result == null) return;
      final database = ref.read(databaseProvider);
      await database.upsertTracks(result.tracks.map(_toCompanion));
      await database.saveScanSource(
        ScanSourcesCompanion.insert(
          id: const Uuid().v5(Namespace.url.value, result.sourceUri),
          platform: result.tracks.firstOrNull?.sourceType ?? 'unknown',
          uri: result.sourceUri,
          label: result.sourceLabel,
          lastScannedAt: Value(DateTime.now()),
        ),
      );
      if (mounted) _showMessage('已导入 ${result.tracks.length} 首歌曲');
    } catch (error) {
      if (mounted) _showMessage('扫描失败：$error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  TracksCompanion _toCompanion(ScannedTrack track) => TracksCompanion.insert(
    id: track.id,
    sourceType: track.sourceType,
    sourceId: track.sourceId,
    uri: track.uri,
    filePath: Value(track.filePath),
    title: track.title,
    artist: Value(track.artist),
    album: Value(track.album),
    durationMs: Value(track.durationMs),
    artwork: Value(track.artwork),
    lyrics: Value(track.lyrics),
    fileSize: Value(track.fileSize),
    modifiedAt: Value(track.modifiedAt),
    updatedAt: DateTime.now(),
  );
}

String _sourceLocation(ScanSource source) {
  if (source.uri == 'media-store://external') {
    return 'Android MediaStore · 整台设备';
  }
  if (source.uri.startsWith('content://')) return 'Android 已授权目录';
  return source.uri;
}
