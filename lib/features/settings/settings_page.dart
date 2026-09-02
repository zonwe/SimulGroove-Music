import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../library/library_scan_settings_section.dart';
import 'appearance_settings_section.dart';
import 'desktop_shortcut_settings_section.dart';
import 'equalizer_settings_section.dart';
import 'now_playing_layout_settings_section.dart';
import 'online_music_settings_section.dart';
import 'settings_section.dart';
import 'tray_settings_section.dart';

/// 设置页：按平台组装各设置区块。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '设置',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        const AppearanceSettingsSection(),
        if (isDesktop) ...[
          const SizedBox(height: 16),
          const NowPlayingLayoutSettingsSection(),
        ],
        const SizedBox(height: 16),
        const EqualizerSettingsSection(),
        const SizedBox(height: 16),
        const LibraryScanSettingsSection(),
        const SizedBox(height: 16),
        const _LibraryInfoSection(),
        const SizedBox(height: 16),
        OnlineMusicSettingsSection(
          downloadSupported: ref.watch(onlineTrackDownloaderProvider).supported,
        ),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) ...[
          const SizedBox(height: 16),
          const TraySettingsSection(),
        ],
        if (isDesktop) ...[
          const SizedBox(height: 16),
          const DesktopShortcutSettingsSection(),
        ],
      ],
    );
  }
}

class _LibraryInfoSection extends StatelessWidget {
  const _LibraryInfoSection();

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: '音乐与同步',
    children: [
      ListTile(
        leading: const Icon(Icons.audio_file_outlined),
        title: const Text('本地格式'),
        subtitle: const Text('MP3、FLAC、M4A/AAC、WAV、OGG、Opus、WMA'),
      ),
      const Divider(height: 1),
      ListTile(
        leading: const Icon(Icons.sync_outlined),
        title: const Text('后台同步'),
        subtitle: const Text('账号登录后自动同步歌单、喜欢歌曲和均衡器预设'),
        trailing: const Chip(label: Text('账号页')),
      ),
    ],
  );
}
