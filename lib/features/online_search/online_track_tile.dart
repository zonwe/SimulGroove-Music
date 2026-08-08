import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/online_music/online_track.dart';

class OnlineTrackTile extends ConsumerWidget {
  const OnlineTrackTile({
    required this.track,
    required this.playbackSupported,
    required this.resolving,
    required this.onPlay,
    super.key,
  });

  final OnlineTrack track;
  final bool playbackSupported;
  final bool resolving;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final artists = track.artists.isEmpty ? '未知艺术家' : track.artists.join('、');
    final details = [
      artists,
      if (track.album.isNotEmpty) track.album,
      if (track.durationMs case final duration?) _formatDuration(duration),
    ].join(' · ');

    return Semantics(
      label: '${track.title}，$artists，来源 ${track.provider}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: _TrackArtwork(
                  artwork: track.capabilities.contains('artwork')
                      ? ref.watch(onlineTrackArtworkProvider(track))
                      : null,
                  title: track.title,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: const Icon(Icons.cloud_outlined, size: 16),
                          label: Text(track.provider),
                          visualDensity: VisualDensity.compact,
                        ),
                        Chip(
                          avatar: Icon(
                            track.playable
                                ? Icons.check_circle_outline
                                : Icons.block_outlined,
                            size: 16,
                          ),
                          label: Text(track.playable ? '来源可播放' : '当前不可播放'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: !track.playable
                    ? '当前来源不可播放'
                    : !playbackSupported
                    ? '当前平台暂不支持在线播放'
                    : resolving
                    ? '正在获取播放地址'
                    : '播放 ${track.title}',
                child: IconButton.filledTonal(
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  onPressed: track.playable && playbackSupported && !resolving
                      ? onPlay
                      : null,
                  icon: resolving
                      ? Semantics(
                          liveRegion: true,
                          label: '正在获取播放地址',
                          child: const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _TrackArtwork extends StatelessWidget {
  const _TrackArtwork({required this.artwork, required this.title});

  final AsyncValue<Uint8List?>? artwork;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colorScheme.secondaryContainer,
      child: Icon(
        artwork?.hasError == true
            ? Icons.broken_image_outlined
            : Icons.music_note_rounded,
        color: colorScheme.onSecondaryContainer,
      ),
    );
    final child = artwork?.when(
      data: (bytes) => bytes == null
          ? fallback
          : Image.memory(
              bytes,
              fit: BoxFit.cover,
              cacheWidth: 96,
              cacheHeight: 96,
              gaplessPlayback: true,
              semanticLabel: '$title 封面',
              errorBuilder: (_, _, _) => fallback,
            ),
      loading: () => ColoredBox(
        color: colorScheme.secondaryContainer,
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
        ),
      ),
      error: (_, _) => fallback,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(dimension: 48, child: child ?? fallback),
    );
  }
}
