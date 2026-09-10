import 'package:flutter/material.dart';

import '../../core/player/equalizer_models.dart';

/// 预设选择行：默认/自定义预设下拉与保存、覆盖、删除、归零操作菜单。
class EqualizerPresetSelector extends StatelessWidget {
  const EqualizerPresetSelector({
    super.key,
    required this.selectedPresetId,
    required this.customPresets,
    required this.currentCustomPreset,
    required this.onSelect,
    required this.onAction,
  });

  final String selectedPresetId;
  final List<EqualizerPreset> customPresets;
  final EqualizerPreset? currentCustomPreset;
  final ValueChanged<EqualizerPreset> onSelect;
  final void Function(EqualizerPresetAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final allPresets = <EqualizerPreset>[
      ...defaultEqualizerPresets,
      ...customPresets,
    ];

    return Row(
      children: [
        // Dropdown
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(selectedPresetId),
            initialValue: allPresets.any((p) => p.id == selectedPresetId)
                ? selectedPresetId
                : 'flat',
            decoration: InputDecoration(
              labelText: '预设配置',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.tune_rounded, size: 20),
            ),

            items: [
              const DropdownMenuItem(
                enabled: false,
                child: Text(
                  '—— 默认预设 ——',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              for (final p in defaultEqualizerPresets)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
              if (customPresets.isNotEmpty) ...[
                const DropdownMenuItem(
                  enabled: false,
                  child: Text(
                    '—— 我的自定义预设 ——',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                for (final p in customPresets)
                  DropdownMenuItem(value: p.id, child: Text('★ ${p.name}')),
              ],
            ],
            onChanged: (val) {
              if (val == null) return;
              final found = allPresets.firstWhere(
                (p) => p.id == val,
                orElse: () => defaultEqualizerPresets.first,
              );
              onSelect(found);
            },
          ),
        ),

        const SizedBox(width: 8),

        // Action menu / Save button
        PopupMenuButton<String>(
          tooltip: '预设操作',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (value) {
            switch (value) {
              case 'save_new':
                onAction(EqualizerPresetAction.saveNew);
              case 'update_current':
                onAction(EqualizerPresetAction.updateCurrent);
              case 'delete_current':
                onAction(EqualizerPresetAction.deleteCurrent);
              case 'reset_flat':
                onAction(EqualizerPresetAction.resetFlat);
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: 'save_new',
              child: ListTile(
                leading: Icon(Icons.add_circle_outline_rounded),
                title: Text('保存为新预设'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (currentCustomPreset != null) ...[
              const PopupMenuItem(
                value: 'update_current',
                child: ListTile(
                  leading: Icon(Icons.save_outlined),
                  title: Text('覆盖更新当前预设'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete_current',
                child: ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red,
                  ),
                  title: Text('删除此自定义预设', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            const PopupMenuItem(
              value: 'reset_flat',
              child: ListTile(
                leading: Icon(Icons.restart_alt_rounded),
                title: Text('归零重置 (平直)'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 预设操作菜单的动作语义，由视图层映射到具体持久化流程。
enum EqualizerPresetAction { saveNew, updateCurrent, deleteCurrent, resetFlat }
