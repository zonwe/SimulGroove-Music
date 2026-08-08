import 'package:flutter/material.dart';

import '../../core/online_music/online_track.dart';

class OnlineTrackTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  color: colorScheme.onSecondaryContainer,
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
