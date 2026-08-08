import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../../core/player/music_audio_handler.dart';
import '../../core/window/desktop_window_controller.dart';
import '../library/artwork_view.dart';
import '../shell/windows_title_bar.dart';
import 'mini_player_bar.dart';
import 'queue_sheet.dart';
import 'volume_control.dart';

class CompactPlayerWindow extends StatelessWidget {
  const CompactPlayerWindow({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Column(
      children: [
        WindowsTitleBar(),
        Expanded(child: CompactPlayer()),
      ],
    ),
  );
}

class CompactPlayer extends ConsumerWidget {
  const CompactPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return LayoutBuilder(
      builder: (context, constraints) {
        return ValueListenableBuilder<bool>(
          valueListenable: DesktopWindowController.compactPanelExpanded,
          builder: (context, panelExpanded, _) {
            final summary = _CompactPlayerSummary(
              handler: handler,
              isAndroid: isAndroid,
            );
            return Column(
              children: [
                if (panelExpanded)
                  SizedBox(
                    height: constraints.maxHeight.clamp(0, 106),
                    child: summary,
                  )
                else
                  Expanded(child: summary),
                if (panelExpanded) ...[
                  const Divider(height: 1),
                  Expanded(
                    child: PlaybackQueuePanel(
                      handler: handler,
                      fillHeight: true,
                      onClose: () => unawaited(
                        DesktopWindowController.setCompactPanelExpanded(false),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _CompactPlayerSummary extends StatelessWidget {
  const _CompactPlayerSummary({required this.handler, required this.isAndroid});

  final MusicAudioHandler handler;
  final bool isAndroid;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showVolume = !isAndroid && constraints.maxWidth >= 440;
          return StreamBuilder<MediaItem?>(
            stream: handler.mediaItem,
            initialData: handler.mediaItem.value,
            builder: (context, itemSnapshot) {
              final item = itemSnapshot.data;
              return Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                child: Row(
                  children: [
                    ArtworkView(
                      bytes: item?.extras?['artwork'] as Uint8List?,
                      size: 76,
                      borderRadius: 10,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StreamBuilder<Duration>(
                        stream: handler.positionStream,
                        builder: (context, snapshot) {
                          final lines = parseLrc(
                            item?.extras?['lyrics'] as String?,
                          );
                          final lyric = lyricAt(
                            lines,
                            snapshot.data ?? Duration.zero,
                          )?.text;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item?.title ?? '还没有播放歌曲',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                item == null
                                    ? '从音乐库选择歌曲'
                                    : lyric ?? item.artist ?? '未知艺术家',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 3),
                              LinearProgressIndicator(
                                value:
                                    playerProgress(
                                      snapshot.data ?? Duration.zero,
                                      item?.duration,
                                    ) ??
                                    0,
                                minHeight: 2,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    StreamBuilder<PlaybackState>(
                      stream: handler.playbackState,
                      initialData: handler.playbackState.value,
                      builder: (context, snapshot) {
                        final playing = snapshot.data?.playing ?? false;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '播放列表',
                              onPressed: item == null
                                  ? null
                                  : () => showPlaybackQueue(context, handler),
                              icon: const Icon(Icons.queue_music_rounded),
                            ),
                            if (showVolume)
                              VolumeControl(
                                handler: handler,
                                showSlider: false,
                              ),
                            IconButton(
                              tooltip: playing ? '暂停' : '播放',
                              onPressed: item == null
                                  ? null
                                  : playing
                                  ? handler.pause
                                  : handler.play,
                              icon: Icon(
                                playing ? Icons.pause : Icons.play_arrow,
                              ),
                            ),
                            IconButton(
                              tooltip: '下一首',
                              onPressed: item == null
                                  ? null
                                  : handler.skipToNext,
                              icon: const Icon(Icons.skip_next),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
