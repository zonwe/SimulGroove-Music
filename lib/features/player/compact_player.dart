import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../library/artwork_view.dart';
import 'mini_player_bar.dart';

class CompactPlayer extends ConsumerWidget {
  const CompactPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, itemSnapshot) {
        final item = itemSnapshot.data;
        if (item == null) return const Center(child: Text('还没有播放歌曲'));
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            children: [
              ArtworkView(
                bytes: item.extras?['artwork'] as Uint8List?,
                size: 76,
                borderRadius: 10,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StreamBuilder<Duration>(
                  stream: handler.positionStream,
                  builder: (context, snapshot) {
                    final lines = parseLrc(item.extras?['lyrics'] as String?);
                    final lyric = lyricAt(
                      lines,
                      snapshot.data ?? Duration.zero,
                    )?.text;
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          lyric ?? item.artist ?? '未知艺术家',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 3),
                        LinearProgressIndicator(
                          value: playerProgress(
                            snapshot.data ?? Duration.zero,
                            item.duration,
                          ),
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
                        tooltip: playing ? '暂停' : '播放',
                        onPressed: playing ? handler.pause : handler.play,
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      ),
                      IconButton(
                        tooltip: '下一首',
                        onPressed: handler.skipToNext,
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
  }
}
