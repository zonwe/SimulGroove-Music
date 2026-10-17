import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/player/lyrics_settings.dart';
import 'settings_section.dart';

/// 歌词交互设置：点击歌词定位播放进度，以及跳转前是否确认。
class LyricsSettingsSection extends ConsumerWidget {
  const LyricsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled =
        ref.watch(lyricsTapToSeekEnabledProvider).value ??
        lyricsTapToSeekEnabledByDefault;
    final confirm =
        ref.watch(lyricsTapToSeekConfirmProvider).value ??
        lyricsTapToSeekConfirmByDefault;
    return SettingsSection(
      title: '歌词',
      children: [
        SwitchListTile(
          value: enabled,
          title: const Text('点击歌词定位播放进度'),
          subtitle: const Text('在正在播放页点按任意歌词行，跳转到该句开始时间'),
          secondary: const Icon(Icons.lyrics_outlined),
          onChanged: (value) => ref
              .read(databaseProvider)
              .setSetting(lyricsTapToSeekSettingKey, value.toString()),
        ),
        const Divider(height: 1),
        SwitchListTile(
          value: confirm,
          title: const Text('跳转前确认'),
          subtitle: Text(
            enabled ? '点按歌词后先确认，避免误触改变播放进度' : '启用“点击歌词定位播放进度”后可设置',
          ),
          secondary: const Icon(Icons.touch_app_outlined),
          onChanged: enabled
              ? (value) => ref
                    .read(databaseProvider)
                    .setSetting(
                      lyricsTapToSeekConfirmSettingKey,
                      value.toString(),
                    )
              : null,
        ),
      ],
    );
  }
}
