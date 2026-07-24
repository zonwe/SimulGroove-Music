import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../library/artwork_view.dart';

class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key});

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage> {
  bool _showLyrics = false;

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('正在播放')),
      body: StreamBuilder<MediaItem?>(
        stream: handler.mediaItem,
        builder: (context, itemSnapshot) {
          final item = itemSnapshot.data;
          if (item == null) return const Center(child: Text('当前没有播放歌曲'));
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
              child: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _showLyrics = !_showLyrics),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _showLyrics
                            ? _LyricsPanel(
                                lyrics: item.extras?['lyrics'] as String?,
                                positionStream: handler.positionStream,
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final size = constraints.biggest.shortestSide
                                      .clamp(180.0, 320.0);
                                  return Center(
                                    child: ArtworkView(
                                      key: const ValueKey('cover'),
                                      bytes:
                                          item.extras?['artwork'] as Uint8List?,
                                      size: size,
                                      borderRadius: 12,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 4),
                      StreamBuilder<Set<String>>(
                        stream: ref.read(databaseProvider).watchLikedTrackIds(),
                        builder: (context, likedSnapshot) {
                          final liked =
                              likedSnapshot.data?.contains(item.id) ?? false;
                          return IconButton(
                            tooltip: liked ? '取消喜欢' : '喜欢',
                            icon: Icon(
                              liked ? Icons.favorite : Icons.favorite_border,
                            ),
                            onPressed: () => ref
                                .read(databaseProvider)
                                .setTrackLiked(item.id, !liked),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.artist ?? '未知艺术家'} · ${item.album ?? '未知专辑'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  StreamBuilder<Duration>(
                    stream: handler.positionStream,
                    builder: (context, positionSnapshot) {
                      final position = positionSnapshot.data ?? Duration.zero;
                      final duration = item.duration ?? Duration.zero;
                      return Column(
                        children: [
                          Slider(
                            value: position.inMilliseconds
                                .clamp(
                                  0,
                                  duration.inMilliseconds == 0
                                      ? 1
                                      : duration.inMilliseconds,
                                )
                                .toDouble(),
                            max: duration.inMilliseconds <= 0
                                ? 1
                                : duration.inMilliseconds.toDouble(),
                            onChanged: (value) => handler.seek(
                              Duration(milliseconds: value.round()),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_format(position)),
                              Text(_format(duration)),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  StreamBuilder<PlaybackState>(
                    stream: handler.playbackState,
                    initialData: handler.playbackState.value,
                    builder: (context, snapshot) {
                      final playing = snapshot.data?.playing ?? false;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton.filledTonal(
                            iconSize: 30,
                            tooltip: '上一首',
                            onPressed: handler.skipToPrevious,
                            icon: const Icon(Icons.skip_previous_rounded),
                          ),
                          const SizedBox(width: 22),
                          IconButton.filled(
                            iconSize: 38,
                            tooltip: playing ? '暂停' : '播放',
                            onPressed: playing ? handler.pause : handler.play,
                            icon: Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                          const SizedBox(width: 22),
                          IconButton.filledTonal(
                            iconSize: 30,
                            tooltip: '下一首',
                            onPressed: handler.skipToNext,
                            icon: const Icon(Icons.skip_next_rounded),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LyricsPanel extends StatelessWidget {
  const _LyricsPanel({required this.lyrics, required this.positionStream});

  final String? lyrics;
  final Stream<Duration> positionStream;

  @override
  Widget build(BuildContext context) {
    final lines = parseLrc(lyrics);
    if (lines.isEmpty) {
      return const Center(key: ValueKey('lyrics-empty'), child: Text('暂无同步歌词'));
    }
    return StreamBuilder<Duration>(
      key: const ValueKey('lyrics'),
      stream: positionStream,
      builder: (context, snapshot) {
        final current = lyricAt(lines, snapshot.data ?? Duration.zero);
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 32),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            final selected = identical(lines[index], current);
            return AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style:
                  (selected
                          ? Theme.of(context).textTheme.titleLarge
                          : Theme.of(context).textTheme.bodyLarge)!
                      .copyWith(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w400,
                        height: 1.8,
                      ),
              child: Text(lines[index].text, textAlign: TextAlign.center),
            );
          },
        );
      },
    );
  }
}

String _format(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
