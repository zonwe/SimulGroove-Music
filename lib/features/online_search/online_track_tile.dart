import 'package:flutter/material.dart';

import '../../core/online_music/online_track.dart';
import 'online_artwork_view.dart';

class OnlineTrackTile extends StatelessWidget {
  const OnlineTrackTile({
    required this.track,
    required this.playbackSupported,
    required this.resolving,
    required this.onPlay,
    this.showArtwork = true,
    this.selected = false,
    this.onSelected,
    this.selectionEnabled = false,
    this.onContextMenuRequested,
    super.key,
  });

  final OnlineTrack track;
  final bool playbackSupported;
  final bool resolving;
  final VoidCallback onPlay;
  final bool showArtwork;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final bool selectionEnabled;
  final ValueChanged<Offset>? onContextMenuRequested;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final artists = track.artists.isEmpty ? '未知艺术家' : track.artists.join('、');
    final details = [
      artists,
      if (track.album.isNotEmpty) track.album,
      track.provider,
      if (track.durationMs case final duration?) _formatDuration(duration),
      if (!track.playable) '不可播放' else if (!playbackSupported) '当前平台不支持播放',
    ].join(' · ');
    final canSelect = selectionEnabled && !resolving && onSelected != null;
    final canPlay =
        !selectionEnabled && track.playable && playbackSupported && !resolving;
    final onTap = canSelect
        ? () => onSelected!(!selected)
        : canPlay
        ? onPlay
        : null;
    final interactionHint = selectionEnabled
        ? selected
              ? '点按取消选择；长按或右键打开歌曲菜单'
              : '点按选择；长按或右键打开歌曲菜单'
        : !track.playable
        ? '当前来源不可播放；长按或右键打开歌曲菜单'
        : !playbackSupported
        ? '当前平台暂不支持在线播放；长按或右键打开歌曲菜单'
        : resolving
        ? '正在获取播放地址'
        : '点按播放；长按或右键打开歌曲菜单';
    Offset fallbackMenuPosition() {
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        return Offset.zero;
      }
      return renderObject.localToGlobal(
        Offset(renderObject.size.width / 2, renderObject.size.height / 2),
      );
    }

    return Semantics(
      label: '${track.title}，$artists，来源 ${track.provider}',
      hint: interactionHint,
      button: onTap != null,
      enabled: onTap != null,
      selected: selectionEnabled ? selected : null,
      onTap: onTap,
      onLongPress: onContextMenuRequested == null
          ? null
          : () => onContextMenuRequested!(fallbackMenuPosition()),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: onContextMenuRequested == null
            ? null
            : (details) => onContextMenuRequested!(details.globalPosition),
        onSecondaryTapDown: onContextMenuRequested == null
            ? null
            : (details) => onContextMenuRequested!(details.globalPosition),
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            excludeFromSemantics: true,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    if (selectionEnabled) ...[
                      Tooltip(
                        message: selected
                            ? '取消选择 ${track.title}'
                            : '选择 ${track.title}',
                        child: Checkbox(
                          value: selected,
                          onChanged: resolving || onSelected == null
                              ? null
                              : (value) => onSelected!(value ?? false),
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                    if (showArtwork) ...[
                      ExcludeSemantics(
                        child: OnlineArtworkView(track: track, size: 44),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            details,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (resolving) ...[
                      const SizedBox(width: 10),
                      Semantics(
                        liveRegion: true,
                        label: '正在获取播放地址',
                        child: const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
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
