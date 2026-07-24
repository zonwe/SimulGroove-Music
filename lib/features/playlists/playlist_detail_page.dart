import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../library/artwork_view.dart';
import '../library/collection_page.dart';

class PlaylistDetailPage extends ConsumerWidget {
  const PlaylistDetailPage({
    super.key,
    required this.playlist,
    required this.onBack,
  });

  final Playlist playlist;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<Track>>(
      stream: ref.read(databaseProvider).watchPlaylistTracks(playlist.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('歌单读取失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final tracks = snapshot.data!;
        final likedIds =
            ref.watch(likedTrackIdsProvider).asData?.value ?? const <String>{};
        return SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final headerTextScale =
                  (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(
                    1.0,
                    1.4,
                  );
              return CustomScrollView(
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _PlaylistHeaderDelegate(
                      playlist: playlist,
                      tracks: tracks,
                      compact: compact,
                      textScale: headerTextScale,
                      onBack: onBack,
                      onPlay: tracks.isEmpty
                          ? null
                          : () => ref
                                .read(audioHandlerProvider)
                                .playTracks(tracks),
                    ),
                  ),
                  if (tracks.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyPlaylist(),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
                        child: Text(
                          '歌曲  ${tracks.length}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      sliver: SliverList.builder(
                        itemCount: tracks.length * 2 - 1,
                        itemBuilder: (context, itemIndex) {
                          if (itemIndex.isOdd) {
                            return const Divider(height: 1, indent: 76);
                          }
                          final index = itemIndex ~/ 2;
                          final track = tracks[index];
                          return ListTile(
                            minTileHeight: 68,
                            leading: ArtworkView(
                              bytes: track.artwork,
                              size: 48,
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${track.artist} · ${track.album}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _trackDuration(track.durationMs),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                IconButton(
                                  tooltip: likedIds.contains(track.id)
                                      ? '取消喜欢'
                                      : '喜欢',
                                  icon: Icon(
                                    likedIds.contains(track.id)
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                  ),
                                  onPressed: () => ref
                                      .read(databaseProvider)
                                      .setTrackLiked(
                                        track.id,
                                        !likedIds.contains(track.id),
                                      ),
                                ),
                                PopupMenuButton<String>(
                                  position: PopupMenuPosition.under,
                                  offset: const Offset(-160, 4),
                                  tooltip: '更多操作',
                                  onSelected: (value) {
                                    if (value == 'artist') {
                                      openCollectionPage(
                                        context,
                                        tracks,
                                        CollectionKind.artist,
                                        track.artist,
                                      );
                                    } else if (value == 'album') {
                                      openCollectionPage(
                                        context,
                                        tracks,
                                        CollectionKind.album,
                                        track.album,
                                      );
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'artist',
                                      child: Text('查看歌手：${track.artist}'),
                                    ),
                                    PopupMenuItem(
                                      value: 'album',
                                      child: Text('查看专辑：${track.album}'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            onTap: () => ref
                                .read(audioHandlerProvider)
                                .playTracks(tracks, initialIndex: index),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _PlaylistHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PlaylistHeaderDelegate({
    required this.playlist,
    required this.tracks,
    required this.compact,
    required this.textScale,
    required this.onBack,
    required this.onPlay,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final bool compact;
  final double textScale;
  final VoidCallback onBack;
  final VoidCallback? onPlay;

  @override
  double get minExtent => 64;

  @override
  double get maxExtent =>
      (compact ? 272 : 284) + math.max(0, textScale - 1) * 80;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final expandedOpacity = (1 - progress * 1.5).clamp(0.0, 1.0);
    final collapsedOpacity = ((progress - 0.55) / 0.45).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.4,
      child: Material(
        color: scheme.surfaceContainerLow,
        elevation: overlapsContent ? 1 : 0,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                top: minExtent,
                child: IgnorePointer(
                  ignoring: progress > 0.45,
                  child: Opacity(
                    opacity: expandedOpacity,
                    child: Transform.translate(
                      offset: Offset(0, -12 * progress),
                      child: _ExpandedPlaylistHeader(
                        playlist: playlist,
                        tracks: tracks,
                        compact: compact,
                        onPlay: onPlay,
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: minExtent,
                  child: Row(
                    children: [
                      BackButton(onPressed: onBack),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Opacity(
                          opacity: collapsedOpacity,
                          child: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      if (onPlay != null)
                        Opacity(
                          opacity: collapsedOpacity,
                          child: IconButton(
                            tooltip: '播放全部',
                            onPressed: collapsedOpacity > 0.5 ? onPlay : null,
                            icon: const Icon(Icons.play_arrow_rounded),
                          ),
                        ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PlaylistHeaderDelegate oldDelegate) {
    return oldDelegate.playlist != playlist ||
        oldDelegate.tracks != tracks ||
        oldDelegate.compact != compact ||
        oldDelegate.textScale != textScale;
  }
}

class _ExpandedPlaylistHeader extends StatelessWidget {
  const _ExpandedPlaylistHeader({
    required this.playlist,
    required this.tracks,
    required this.compact,
    required this.onPlay,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final bool compact;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final artworkSize = compact ? 132.0 : 172.0;
    final totalDuration = tracks.fold<int>(
      0,
      (total, track) => total + (track.durationMs ?? 0),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 20 : 28, 8, compact ? 20 : 28, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ArtworkView(
            bytes: tracks.firstOrNull?.artwork,
            size: artworkSize,
            borderRadius: 10,
          ),
          SizedBox(width: compact ? 16 : 24),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '歌单',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  playlist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (compact
                              ? Theme.of(context).textTheme.headlineSmall
                              : Theme.of(context).textTheme.headlineMedium)
                          ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  _playlistSummary(tracks.length, totalDuration),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放全部'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPlaylist extends StatelessWidget {
  const _EmptyPlaylist();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.playlist_add_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          Text('歌单中还没有歌曲', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '可以从音乐库将歌曲添加到这里',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

String _trackDuration(int? milliseconds) {
  if (milliseconds == null) return '--:--';
  final duration = Duration(milliseconds: milliseconds);
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _playlistSummary(int count, int milliseconds) {
  if (milliseconds <= 0) return '$count 首歌曲';
  final duration = Duration(milliseconds: milliseconds);
  final hours = duration.inHours;
  final minutes = math.max(1, duration.inMinutes.remainder(60));
  return hours > 0
      ? '$count 首歌曲 · $hours 小时 $minutes 分钟'
      : '$count 首歌曲 · $minutes 分钟';
}
