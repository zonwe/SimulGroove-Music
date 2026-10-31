import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import 'artwork_view.dart';
import '../player/playback_navigation.dart';

class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(likedTracksProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '喜欢的音乐',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: tracks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('读取喜欢的音乐失败：$error')),
              data: (items) => items.isEmpty
                  ? const Center(child: Text('还没有喜欢的音乐'))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 18),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) => _FavoriteTile(
                        track: items[index],
                        tracks: items,
                        index: index,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteTile extends ConsumerWidget {
  const _FavoriteTile({
    required this.track,
    required this.tracks,
    required this.index,
  });

  final Track track;
  final List<Track> tracks;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    minTileHeight: 64,
    leading: TrackArtworkView(trackId: track.id),
    title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '${track.artist} · ${track.album}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: IconButton(
      tooltip: '取消喜欢',
      icon: const Icon(Icons.favorite),
      onPressed: () =>
          ref.read(databaseProvider).setTrackLiked(track.id, false),
    ),
    onTap: () =>
        playOrOpenNowPlaying(context, ref, tracks, initialIndex: index),
  );
}
