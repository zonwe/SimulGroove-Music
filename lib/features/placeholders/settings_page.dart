import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../app/providers.dart';
import '../../core/online_music/online_search_settings.dart';
import '../../core/online_music/online_track_downloader.dart';
import '../../core/player/equalizer_models.dart';
import '../../core/player/now_playing_layout.dart';
import '../../core/theme/app_appearance.dart';
import '../../core/shortcuts/desktop_shortcut_service.dart';
import '../../core/window/desktop_window_controller.dart';
import '../../core/window/window_settings.dart';
import '../equalizer/equalizer_view.dart';
import '../library/library_scan_settings_section.dart';
import 'desktop_shortcut_settings_section.dart';

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
    final isDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
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
                    subtitle: Text('默认跟随系统的浅色或深色设置'),
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
        if (isDesktop) ...[
          const SizedBox(height: 16),
          const NowPlayingLayoutSettingsSection(),
        ],
        const SizedBox(height: 16),
        const _EqualizerSection(),
        const SizedBox(height: 16),
        const LibraryScanSettingsSection(),
        const SizedBox(height: 16),
        const _SettingsSection(
          title: '音乐与同步',
          children: [
            ListTile(
              leading: Icon(Icons.audio_file_outlined),
              title: Text('本地格式'),
              subtitle: Text('MP3、FLAC、M4A/AAC、WAV、OGG、Opus、WMA'),
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
        const SizedBox(height: 16),
        _OnlineMusicSettingsSection(
          downloadSupported: ref.watch(onlineTrackDownloaderProvider).supported,
        ),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) ...[
          const SizedBox(height: 16),
          const _TraySettingsSection(),
        ],
        if (isDesktop) ...[
          const SizedBox(height: 16),
          const DesktopShortcutSettingsSection(),
        ],
      ],
    );
  }
}

@visibleForTesting
class NowPlayingLayoutSettingsSection extends ConsumerWidget {
  const NowPlayingLayoutSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout =
        ref.watch(nowPlayingLayoutProvider).value ?? NowPlayingLayout.classic;
    return _SettingsSection(
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

class _OnlineMusicSettingsSection extends ConsumerStatefulWidget {
  const _OnlineMusicSettingsSection({required this.downloadSupported});

  final bool downloadSupported;

  @override
  ConsumerState<_OnlineMusicSettingsSection> createState() =>
      _OnlineMusicSettingsSectionState();
}

class _OnlineMusicSettingsSectionState
    extends ConsumerState<_OnlineMusicSettingsSection> {
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
    return _SettingsSection(
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

// ignore: unused_element, kept as a compatibility reference for older builds.
class _ShortcutSettingsSection extends ConsumerWidget {
  const _ShortcutSettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = DesktopShortcutService.instance;
    return ValueListenableBuilder<HotKeyScope>(
      valueListenable: service.scope,
      builder: (context, currentScope, _) => _SettingsSection(
        title: 'Windows 快捷键',
        children: [
          ListTile(
            leading: const Icon(Icons.keyboard_alt_outlined),
            title: const Text('快捷键作用域'),
            subtitle: const Text('全局模式在其他应用前台时也响应；应用内模式只在本应用窗口激活时响应'),
            trailing: DropdownButton<HotKeyScope>(
              value: currentScope,
              items: const [
                DropdownMenuItem(value: HotKeyScope.system, child: Text('全局')),
                DropdownMenuItem(value: HotKeyScope.inapp, child: Text('应用内')),
              ],
              onChanged: (value) {
                if (value != null) service.setScope(value);
              },
            ),
          ),
          const Divider(height: 1),
          for (final action in DesktopShortcutAction.values)
            _ShortcutRow(action: action, service: service),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text('默认不分配快捷键；录制后才会启用对应操作。'),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: service.lastError,
            builder: (context, error, _) {
              if (error == null || error.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              '注册失败通常表示该组合已被其他应用或系统占用；重新录制后会立即检测。退出快捷键会直接退出应用，不受托盘最小化设置影响。',
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.action, required this.service});

  final DesktopShortcutAction action;
  final DesktopShortcutService service;

  @override
  Widget build(BuildContext context) {
    final hotKey = service.hotKeyFor(action);
    return ListTile(
      leading: Icon(_shortcutIcon(action)),
      title: Text(action.label),
      trailing: SizedBox(
        width: 180,
        child: HotKeyRecorder(
          initalHotKey: hotKey,
          onHotKeyRecorded: (recorded) async {
            await service.update(action, recorded);
          },
        ),
      ),
    );
  }
}

IconData _shortcutIcon(DesktopShortcutAction action) => switch (action) {
  DesktopShortcutAction.togglePlay => Icons.play_arrow,
  DesktopShortcutAction.previous => Icons.skip_previous,
  DesktopShortcutAction.next => Icons.skip_next,
  DesktopShortcutAction.showWindow => Icons.open_in_new,
  DesktopShortcutAction.toggleWindow => Icons.picture_in_picture_alt_outlined,
  DesktopShortcutAction.quit => Icons.exit_to_app,
};

class _EqualizerSection extends ConsumerWidget {
  const _EqualizerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customPresets =
        ref.watch(customEqualizerPresetsProvider).value ?? const [];
    return StreamBuilder<Map<String, String>>(
      stream: ref.watch(databaseProvider).watchSettings(),
      builder: (context, snapshot) {
        final settings = snapshot.data ?? const <String, String>{};
        final enabled = settings['audio.equalizer.enabled'] != 'false';
        final presetId = settings['audio.equalizer.preset'] ?? 'flat';

        String presetName = '平直';
        final defaultPreset = findDefaultEqualizerPreset(presetId);
        if (defaultPreset != null) {
          presetName = defaultPreset.name;
        } else {
          for (final cp in customPresets) {
            if (cp.id == presetId) {
              presetName = '★ ${cp.name}';
              break;
            }
          }
        }

        return _SettingsSection(
          title: '播放音效',
          children: [
            ListTile(
              leading: Icon(
                Icons.equalizer_rounded,
                color: enabled ? Theme.of(context).colorScheme.primary : null,
              ),
              title: const Text('音频均衡器'),
              subtitle: Text(
                enabled ? '10 频段实时 DSP 调节 · 当前预设：$presetName' : '均衡器已禁用',
              ),
              trailing: FilledButton.tonalIcon(
                onPressed: () => EqualizerView.show(context),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('调节'),
              ),
              onTap: () => EqualizerView.show(context),
            ),
          ],
        );
      },
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
