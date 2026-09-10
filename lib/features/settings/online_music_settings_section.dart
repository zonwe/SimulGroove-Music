import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/online_music/online_search_settings.dart';
import '../../core/online_music/online_track_downloader.dart';
import 'settings_section.dart';

/// 在线音乐设置：搜索封面、下载目录与下载文件命名。
class OnlineMusicSettingsSection extends ConsumerStatefulWidget {
  const OnlineMusicSettingsSection({
    super.key,
    required this.downloadSupported,
  });

  final bool downloadSupported;

  @override
  ConsumerState<OnlineMusicSettingsSection> createState() =>
      _OnlineMusicSettingsSectionState();
}

class _OnlineMusicSettingsSectionState
    extends ConsumerState<OnlineMusicSettingsSection> {
  String? _destinationLabel;
  bool _loading = true;
  bool _choosing = false;

  @override
  void initState() {
    super.initState();
    if (widget.downloadSupported) {
      unawaited(_loadDestination());
    } else {
      _loading = false;
    }
  }

  Future<void> _loadDestination() async {
    try {
      final destination = await ref
          .read(onlineTrackDownloaderProvider)
          .destination();
      if (!mounted) return;
      setState(() {
        _destinationLabel = destination?.label;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('无法读取下载目录：$error');
    }
  }

  Future<void> _chooseDestination() async {
    if (_choosing) return;
    setState(() => _choosing = true);
    try {
      final destination = await ref
          .read(onlineTrackDownloaderProvider)
          .chooseDestination();
      if (!mounted || destination == null) return;
      setState(() => _destinationLabel = destination.label);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('下载目录已设为：${destination.label}')));
    } catch (error) {
      if (mounted) _showError('无法设置下载目录：$error');
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final showArtwork =
        ref.watch(onlineSearchShowArtworkProvider).value ?? true;
    final filenameFormat =
        ref.watch(onlineDownloadFilenameFormatProvider).value ??
        OnlineDownloadFilenameFormat.artistTitle;
    return SettingsSection(
      title: '在线音乐',
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.image_outlined),
          title: const Text('显示搜索结果封面'),
          subtitle: const Text('关闭后不加载封面，搜索结果会更紧凑'),
          value: showArtwork,
          onChanged: (value) => ref
              .read(databaseProvider)
              .setSetting(onlineSearchShowArtworkSettingKey, '$value'),
        ),
        if (widget.downloadSupported) ...[
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('下载目录'),
            subtitle: Text(
              _loading ? '正在读取…' : _destinationLabel ?? '尚未设置；下载在线歌曲前需要先选择目录',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _loading
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton.tonalIcon(
                    onPressed: _choosing ? null : _chooseDestination,
                    icon: _choosing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.folder_open_outlined),
                    label: Text(_destinationLabel == null ? '选择' : '更改'),
                  ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text('Windows、Linux 和 Android 会记住此目录；搜索页只负责选择歌曲和开始下载。'),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: DropdownButtonFormField<OnlineDownloadFilenameFormat>(
              initialValue: filenameFormat,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.drive_file_rename_outline),
                labelText: '下载文件命名',
                helperText: '选择默认文件名顺序，不改变音频编码格式',
              ),
              items: const [
                DropdownMenuItem(
                  value: OnlineDownloadFilenameFormat.artistTitle,
                  child: Text('歌手 - 歌曲名'),
                ),
                DropdownMenuItem(
                  value: OnlineDownloadFilenameFormat.titleArtist,
                  child: Text('歌曲名 - 歌手'),
                ),
                DropdownMenuItem(
                  value: OnlineDownloadFilenameFormat.titleOnly,
                  child: Text('只有歌曲名'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                ref
                    .read(databaseProvider)
                    .setSetting(
                      onlineDownloadFilenameFormatSettingKey,
                      serializeOnlineDownloadFilenameFormat(value),
                    );
              },
            ),
          ),
        ],
      ],
    );
  }
}
