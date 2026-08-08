import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../core/shortcuts/desktop_shortcut_service.dart';

class DesktopShortcutSettingsSection extends StatelessWidget {
  const DesktopShortcutSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final service = DesktopShortcutService.instance;
    return ValueListenableBuilder<int>(
      valueListenable: service.revision,
      builder: (context, _, child) => _SettingsCard(
        title: 'Windows 快捷键',
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.keyboard_alt_outlined),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '快捷键绑定',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: service.clearAll,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('清空全部'),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('默认不绑定快捷键。点击按钮后，在弹出的小窗口中按下组合键并保存。'),
              ),
            ),
            const Divider(height: 1),
            const _ShortcutHeader(),
            for (final action in DesktopShortcutAction.values)
              _ShortcutRow(action: action, service: service),
            ValueListenableBuilder<String?>(
              valueListenable: service.lastError,
              builder: (context, error, _) {
                if (error == null || error.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      Card(child: child),
    ],
  );
}

class _ShortcutHeader extends StatelessWidget {
  const _ShortcutHeader();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
    child: Row(
      children: [
        SizedBox(width: 180, child: Text('功能说明')),
        Expanded(child: Text('应用内快捷键')),
        Expanded(child: Text('全局快捷键')),
      ],
    ),
  );
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.action, required this.service});

  final DesktopShortcutAction action;
  final DesktopShortcutService service;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: Row(
      children: [
        SizedBox(
          width: 180,
          child: Row(
            children: [
              Icon(_shortcutIcon(action), size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(action.label)),
            ],
          ),
        ),
        Expanded(child: _ShortcutCell(action, HotKeyScope.inapp, service)),
        Expanded(child: _ShortcutCell(action, HotKeyScope.system, service)),
      ],
    ),
  );
}

class _ShortcutCell extends StatelessWidget {
  const _ShortcutCell(this.action, this.scope, this.service);

  final DesktopShortcutAction action;
  final HotKeyScope scope;
  final DesktopShortcutService service;

  @override
  Widget build(BuildContext context) {
    final hotKey = service.hotKeyFor(action, scope);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final recorded = await _showShortcutDialog(
                  context,
                  action: action,
                  scope: scope,
                  initial: hotKey,
                );
                if (recorded == null) return;
                await service.update(action, scope, recorded);
              },
              icon: const Icon(Icons.keyboard_outlined, size: 18),
              label: Text(
                hotKey == null ? '点击绑定' : _formatHotKey(hotKey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (hotKey != null)
            IconButton(
              tooltip: '删除绑定',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => service.remove(action, scope),
            ),
        ],
      ),
    );
  }
}

Future<HotKey?> _showShortcutDialog(
  BuildContext context, {
  required DesktopShortcutAction action,
  required HotKeyScope scope,
  required HotKey? initial,
}) => showDialog<HotKey>(
  context: context,
  builder: (context) =>
      _ShortcutDialog(action: action, scope: scope, initial: initial),
);

class _ShortcutDialog extends StatefulWidget {
  const _ShortcutDialog({
    required this.action,
    required this.scope,
    required this.initial,
  });

  final DesktopShortcutAction action;
  final HotKeyScope scope;
  final HotKey? initial;

  @override
  State<_ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends State<_ShortcutDialog> {
  final FocusNode _focusNode = FocusNode();
  HotKey? _recorded;

  @override
  void initState() {
    super.initState();
    _recorded = widget.initial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final isModifierOnly =
        event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight ||
        event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight ||
        event.logicalKey == LogicalKeyboardKey.altLeft ||
        event.logicalKey == LogicalKeyboardKey.altRight ||
        event.logicalKey == LogicalKeyboardKey.metaLeft ||
        event.logicalKey == LogicalKeyboardKey.metaRight;
    if (event is! KeyDownEvent || isModifierOnly) {
      return KeyEventResult.handled;
    }
    final pressed = HardwareKeyboard.instance.physicalKeysPressed;
    final modifiers = HotKeyModifier.values
        .where((modifier) => modifier.physicalKeys.any(pressed.contains))
        .toList();
    setState(() {
      _recorded = HotKey(
        key: event.physicalKey,
        modifiers: modifiers,
        scope: widget.scope,
      );
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final current = _recorded;
    return AlertDialog(
      title: Text('绑定${widget.action.label}'),
      content: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKeyEvent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.keyboard_rounded, size: 32),
              const SizedBox(height: 12),
              Text(
                current == null ? '请按下快捷键组合' : _formatHotKey(current),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.scope == HotKeyScope.system ? '全局快捷键' : '应用内快捷键',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: current == null
              ? null
              : () => Navigator.of(context).pop(current),
          child: const Text('保存'),
        ),
      ],
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

String _formatHotKey(HotKey hotKey) {
  final modifiers = (hotKey.modifiers ?? const <HotKeyModifier>[]).map(
    (modifier) => switch (modifier) {
      HotKeyModifier.control => 'Ctrl',
      HotKeyModifier.alt => 'Alt',
      HotKeyModifier.shift => 'Shift',
      HotKeyModifier.meta => 'Win',
      HotKeyModifier.capsLock => 'Caps Lock',
      HotKeyModifier.fn => 'Fn',
    },
  );
  final key = (hotKey.physicalKey.debugName ?? hotKey.logicalKey.keyLabel)
      .replaceFirst('Left', '')
      .replaceFirst('Right', '')
      .replaceFirst('Key ', '');
  return [...modifiers, key].join(' + ');
}
