import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/window/desktop_drag_area.dart';
import '../../core/window/desktop_window_controller.dart';

class WindowsTitleBar extends StatelessWidget {
  const WindowsTitleBar({super.key});

  static bool get isVisible =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            Expanded(
              child: DesktopDragArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.music_note_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'SimulGroove Music',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _WindowButton(
              icon: Icons.picture_in_picture_alt_outlined,
              tooltip: '切换悬浮播放器',
              onPressed: DesktopWindowController.toggleCompact,
            ),
            _WindowButton(
              icon: Icons.remove,
              tooltip: '最小化',
              onPressed: DesktopWindowController.minimize,
            ),
            _WindowButton(
              icon: Icons.close,
              tooltip: '关闭',
              isClose: true,
              onPressed: DesktopWindowController.close,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onPressed,
      hoverColor: isClose
          ? const Color(0xFFC42B1C)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(width: 48, height: 38, child: Icon(icon, size: 18)),
    ),
  );
}
