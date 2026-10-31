import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/format/duration_text.dart';
import '../../core/library/artist_names.dart';
import 'artwork_view.dart';
import '../player/mini_player_bar.dart';
import '../player/playback_navigation.dart';

enum CollectionKind { artist, album }

class CollectionPage extends ConsumerWidget {
  const CollectionPage({
    super.key,
    required this.kind,
    required this.value,
    required this.tracks,
  });

  final CollectionKind kind;
  final String value;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = kind == CollectionKind.artist ? '歌手' : '专辑';
    return Scaffold(
      appBar: AppBar(title: Text(value)),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final track = tracks[index];
          return ListTile(
            minTileHeight: 64,
            leading: TrackArtworkView(trackId: track.id),
            title: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              kind == CollectionKind.artist ? track.album : track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(formatTrackDuration(track.durationMs)),
            onTap: () =>
                playOrOpenNowPlaying(context, ref, tracks, initialIndex: index),
          );
        },
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayerBar(),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Text(
              '$label · ${tracks.length} 首歌曲',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openArtistCollectionPage(
  BuildContext context,
  List<Track> allTracks,
  String artistTag,
) async {
  final artists = splitArtistNames(artistTag);
  if (artists.isEmpty) return;

  if (artists.length == 1) {
    openCollectionPage(
      context,
      allTracks,
      CollectionKind.artist,
      artists.single,
    );
    return;
  }

  final selectedArtist = await showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('选择歌手'),
      children: [
        for (final artist in artists)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(artist),
            child: Text(artist),
          ),
      ],
    ),
  );
  if (!context.mounted || selectedArtist == null) return;

  openCollectionPage(context, allTracks, CollectionKind.artist, selectedArtist);
}

void openCollectionPage(
  BuildContext context,
  List<Track> allTracks,
  CollectionKind kind,
  String value,
) {
  final tracks = allTracks
      .where(
        (track) => kind == CollectionKind.artist
            ? artistTagContains(track.artist, value)
            : track.album == value,
      )
      .toList(growable: false);
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CollectionPage(kind: kind, value: value, tracks: tracks),
    ),
  );
}
