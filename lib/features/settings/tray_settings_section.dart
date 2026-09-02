import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/window/desktop_window_controller.dart';
import '../../core/window/window_settings.dart';
import 'settings_section.dart';

/// 窗口与托盘设置；仅 Windows 展示。
class TraySettingsSection extends ConsumerWidget {
  const TraySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(trayMinimizeOnCloseProvider).value ?? true;
    return SettingsSection(
      title: '窗口与托盘',
      children: [
        SwitchListTile(
          value: enabled,
          title: const Text('关闭时最小化到托盘'),
          subtitle: const Text('点击右上角关闭后，程序继续在 Windows 托盘运行'),
          secondary: const Icon(Icons.notifications_none_outlined),
          onChanged: (value) async {
            await ref
                .read(databaseProvider)
                .setSetting(trayMinimizeOnCloseSettingKey, value.toString());
            await DesktopWindowController.setMinimizeToTray(value);
          },
        ),
      ],
    );
  }
}
