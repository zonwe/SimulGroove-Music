import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_appearance.dart';
import '../../core/window/desktop_window_controller.dart';
import '../../core/window/window_settings.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const _themeColors = <(String, Color)>[
    ('靛蓝', Color(0xFF536DFE)),
    ('蓝色', Color(0xFF1976D2)),
    ('青色', Color(0xFF00897B)),
    ('绿色', Color(0xFF43A047)),
    ('橙色', Color(0xFFF57C00)),
    ('红色', Color(0xFFE53935)),
    ('粉色', Color(0xFFD81B60)),
    ('紫色', Color(0xFF7E57C2)),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance =
        ref.watch(appearanceProvider).value ??
        const AppAppearance(
          themeMode: ThemeMode.system,
          seedColor: defaultThemeColor,
        );
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
        _SettingsSection(
          title: '外观',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ListTile(
                    leading: Icon(Icons.brightness_6_outlined),
                    title: Text('显示模式'),
                    subtitle: Text('默认跟随 Android、Windows 或浏览器的系统设置'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('系统'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('浅色'),
                        ),
                        ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                      ],
                      selected: {appearance.themeMode},
                      onSelectionChanged: (value) => ref
                          .read(databaseProvider)
                          .setSetting(
                            themeModeSettingKey,
                            serializeThemeMode(value.first),
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.palette_outlined),
                      SizedBox(width: 16),
                      Text('主题色'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: Text(
                      '按钮、选中状态、进度和强调色会围绕所选颜色生成',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final option in _themeColors)
                        _ColorChoice(
                          label: option.$1,
                          color: option.$2,
                          selected:
                              option.$2.toARGB32() ==
                              appearance.seedColor.toARGB32(),
                          onTap: () => ref
                              .read(databaseProvider)
                              .setSetting(
                                themeColorSettingKey,
                                option.$2.toARGB32().toString(),
                              ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _SettingsSection(
          title: '音乐与同步',
          children: [
            ListTile(
              leading: Icon(Icons.audio_file_outlined),
              title: Text('本地格式'),
              subtitle: Text('MP3、FLAC、M4A/AAC、WAV、OGG、Opus；Windows 尝试支持 WMA'),
            ),
            Divider(height: 1),
            ListTile(
              leading: Icon(Icons.sync_outlined),
              title: Text('后台同步'),
              subtitle: Text('尚未连接服务器'),
              trailing: Chip(label: Text('预留')),
            ),
          ],
        ),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) ...[
          const SizedBox(height: 16),
          const _TraySettingsSection(),
        ],
      ],
    );
  }
}

class _TraySettingsSection extends ConsumerWidget {
  const _TraySettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(trayMinimizeOnCloseProvider).value ?? true;
    return _SettingsSection(
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

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      Card(child: Column(children: children)),
    ],
  );
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label主题色',
    selected: selected,
    button: true,
    child: Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: selected ? 3 : 0,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  color:
                      ThemeData.estimateBrightnessForColor(color) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                )
              : null,
        ),
      ),
    ),
  );
}
