import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../library/artwork_view.dart';
import 'now_playing_page.dart';

class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key, this.onReturn});

  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, itemSnapshot) {
        final item = itemSnapshot.data;
        if (item == null) return const SizedBox.shrink();
        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          initialData: handler.playbackState.value,
          builder: (context, stateSnapshot) {
            final state = stateSnapshot.data!;
            return Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: InkWell(
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NowPlayingPage()),
                  );
                  onReturn?.call();
                },
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 76,
                    child: Column(
                      children: [
                        StreamBuilder<Duration>(
                          stream: handler.positionStream,
                          builder: (context, position) =>
                              LinearProgressIndicator(
                                minHeight: 2,
                                value: playerProgress(
                                  position.data ?? Duration.zero,
                                  item.duration,
                                ),
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                              ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                ArtworkView(
                                  bytes: item.extras?['artwork'] as Uint8List?,
                                  size: 48,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _NowPlayingText(
                                    item: item,
                                    positionStream: handler.positionStream,
                                  ),
                                ),
                                IconButton(
                                  tooltip: state.playing ? '暂停' : '播放',
                                  onPressed: state.playing
                                      ? handler.pause
                                      : handler.play,
                                  icon: Icon(
                                    state.playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '下一首',
                                  onPressed: handler.skipToNext,
                                  icon: const Icon(Icons.skip_next_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _NowPlayingText extends StatelessWidget {
  const _NowPlayingText({required this.item, required this.positionStream});

  final MediaItem item;
  final Stream<Duration> positionStream;

  @override
  Widget build(BuildContext context) {
    final lines = parseLrc(item.extras?['lyrics'] as String?);
    return StreamBuilder<Duration>(
      stream: positionStream,
      builder: (context, snapshot) {
        final lyric = lyricAt(lines, snapshot.data ?? Duration.zero)?.text;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              lyric == null || lyric.isEmpty ? (item.artist ?? '未知艺术家') : lyric,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: lyric == null
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        );
      },
    );
  }
}

double? playerProgress(Duration position, Duration? duration) {
  if (duration == null || duration.inMilliseconds <= 0) return null;
  return (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
}
