import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/player/equalizer_models.dart';
import '../equalizer/equalizer_view.dart';
import 'settings_section.dart';

/// 播放音效设置：均衡器入口与当前预设摘要。
class EqualizerSettingsSection extends ConsumerWidget {
  const EqualizerSettingsSection({super.key});

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

        return SettingsSection(
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
