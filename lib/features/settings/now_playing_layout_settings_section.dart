import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/player/now_playing_layout.dart';
import 'settings_section.dart';

/// 播放界面布局设置；桌面端展示。
class NowPlayingLayoutSettingsSection extends ConsumerWidget {
  const NowPlayingLayoutSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout =
        ref.watch(nowPlayingLayoutProvider).value ?? NowPlayingLayout.classic;
    return SettingsSection(
      title: '播放界面',
      children: [
        const ListTile(
          leading: Icon(Icons.view_week_outlined),
          title: Text('正在播放页布局'),
          subtitle: Text('双栏模式在宽窗口显示左侧封面和右侧歌词；窄窗口会自动使用经典模式'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<NowPlayingLayout>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: NowPlayingLayout.classic,
                  icon: Icon(Icons.crop_square_rounded),
                  label: Text('经典'),
                ),
                ButtonSegment(
                  value: NowPlayingLayout.split,
                  icon: Icon(Icons.view_week_rounded),
                  label: Text('封面歌词双栏'),
                ),
              ],
              selected: {layout},
              onSelectionChanged: (selection) => ref
                  .read(databaseProvider)
                  .setSetting(
                    nowPlayingLayoutSettingKey,
                    serializeNowPlayingLayout(selection.first),
                  ),
            ),
          ),
        ),
      ],
    );
  }
}
