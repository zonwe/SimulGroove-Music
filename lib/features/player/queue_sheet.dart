import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/player/music_audio_handler.dart';
import '../../core/window/desktop_window_controller.dart';
import '../library/artwork_view.dart';

final playbackQueueDockOpen = ValueNotifier<bool>(false);

/// Opens the transient playback queue (the tracks loaded into the player).
/// This is separate from the persisted playlists stored in the database.
Future<void> showPlaybackQueue(
  BuildContext context,
  MusicAudioHandler handler,
) async {
  final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  if (isWindows && DesktopWindowController.compactMode.value) {
    await DesktopWindowController.setCompactPanelExpanded(
      !DesktopWindowController.compactPanelExpanded.value,
    );
    return;
  }
  if (isWindows && MediaQuery.sizeOf(context).width >= 900) {
    playbackQueueDockOpen.value = !playbackQueueDockOpen.value;
    return;
  }
  playbackQueueDockOpen.value = false;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) =>
        PlaybackQueuePanel(handler: handler, closeOnSelection: true),
  );
}

class PlaybackQueuePanel extends StatelessWidget {
  const PlaybackQueuePanel({
    super.key,
    required this.handler,
    this.fillHeight = false,
    this.closeOnSelection = false,
    this.onClose,
  });

  final MusicAudioHandler handler;
  final bool fillHeight;
  final bool closeOnSelection;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: StreamBuilder<List<MediaItem>>(
          stream: handler.queue,
          initialData: handler.queue.value,
          builder: (context, queueSnapshot) {
            final items = queueSnapshot.data ?? const <MediaItem>[];
            return StreamBuilder<PlaybackState>(
              stream: handler.playbackState,
              initialData: handler.playbackState.value,
              builder: (context, stateSnapshot) {
                final currentIndex = stateSnapshot.data?.queueIndex;
                return ConstrainedBox(
                  constraints: fillHeight
                      ? const BoxConstraints()
                      : const BoxConstraints(maxHeight: 560),
                  child: Column(
                    mainAxisSize: fillHeight
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '播放列表${items.isEmpty ? '' : ' · ${items.length} 首'}',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              tooltip: '关闭播放列表',
                              onPressed: () {
                                final close = onClose;
                                if (close != null) {
                                  close();
                                } else {
                                  Navigator.of(context).pop();
                                }
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 24, 20, 32),
                          child: Text('当前没有待播放的歌曲'),
                        )
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.only(bottom: 12),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1, indent: 76),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final selected = index == currentIndex;
                              return ListTile(
                                selected: selected,
                                selectedTileColor: Theme.of(
                                  context,
                                ).colorScheme.secondaryContainer,
                                leading: ArtworkView(
                                  bytes: item.extras?['artwork'] as Uint8List?,
                                  size: 48,
                                ),
                                title: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  item.artist ?? '未知艺术家',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: selected
                                    ? Icon(
                                        Icons.equalizer_rounded,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      )
                                    : null,
                                onTap: () async {
                                  await handler.skipToQueueItem(index);
                                  if (context.mounted && closeOnSelection) {
                                    Navigator.of(context).pop();
                                  }
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
