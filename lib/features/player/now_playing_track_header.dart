import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/library/artist_names.dart';
import '../../core/online_music/online_track.dart';
import '../library/collection_page.dart';
import '../online_search/online_collection_page.dart';

/// 从 MediaItem 的 extras 还原在线曲目；非在线来源返回 null。
OnlineTrack? onlineTrackFromMediaItem(MediaItem item) {
  final extras = item.extras;
  if (extras?['sourceType'] != 'online') return null;
  final provider = extras?['provider'] as String?;
  final trackId = extras?['trackId'] as String?;
  if (provider == null ||
      provider.trim().isEmpty ||
      trackId == null ||
      trackId.trim().isEmpty) {
    return null;
  }
  final lyrics = extras?['lyrics'] as String?;
  return OnlineTrack(
    provider: provider,
    trackId: trackId,
    title: item.title,
    artists: splitArtistNames(item.artist ?? ''),
    album: item.album ?? '',
    durationMs: item.duration?.inMilliseconds,
    playable: true,
    capabilities: {'playback', if (lyrics?.trim().isNotEmpty == true) 'lyrics'},
  );
}

/// 打开歌手集合页；在线曲目走在线集合，本地曲目走本地集合。
Future<void> openNowPlayingArtist(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
  String artist,
) async {
  final onlineTrack = onlineTrackFromMediaItem(item);
  if (onlineTrack != null) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => OnlineCollectionPage(
          request: OnlineCollectionRequest(
            kind: OnlineCollectionKind.artist,
            value: artist,
            seedTracks: [onlineTrack],
          ),
          onBack: () => Navigator.of(routeContext).pop(),
          standalone: true,
        ),
      ),
    );
    return;
  }

  final tracks = await ref.read(databaseProvider).allTracks();
  if (!context.mounted) return;
  openCollectionPage(context, tracks, CollectionKind.artist, artist);
}

/// 歌曲标题行：标题与喜欢按钮。
class NowPlayingTrackTitleRow extends ConsumerWidget {
  const NowPlayingTrackTitleRow({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            item.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 4),
        _LikedToggle(trackId: item.id),
      ],
    );
  }
}

/// 喜欢按钮。
///
/// 不要在 `build` 里 `ref.read(db).watchLikedTrackIds()`：StreamBuilder 每次重建
/// 都会新建一条流和一次查询；共用 `likedTrackIdsProvider` 只保留一条订阅。
class _LikedToggle extends ConsumerWidget {
  const _LikedToggle({required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked =
        ref.watch(likedTrackIdsProvider).value?.contains(trackId) ?? false;
    return IconButton(
      tooltip: liked ? '取消喜欢' : '喜欢',
      icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
      onPressed: () =>
          ref.read(databaseProvider).setTrackLiked(trackId, !liked),
    );
  }
}

/// 歌手与专辑链接行。
class NowPlayingArtistLinks extends StatelessWidget {
  const NowPlayingArtistLinks({
    super.key,
    required this.artistTag,
    required this.album,
    required this.onArtistTap,
  });

  final String artistTag;
  final String album;
  final ValueChanged<String> onArtistTap;

  @override
  Widget build(BuildContext context) {
    final artists = splitArtistNames(artistTag);
    final displayArtists = artists.isEmpty ? const ['未知艺术家'] : artists;
    final secondaryStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final children = <Widget>[];
    for (var index = 0; index < displayArtists.length; index++) {
      final artist = displayArtists[index];
      if (index > 0) {
        children.add(Text('/', style: secondaryStyle));
      }
      if (artist == '未知艺术家') {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(artist, style: secondaryStyle),
          ),
        );
      } else {
        children.add(
          Tooltip(
            message: '查看歌手：$artist',
            child: TextButton(
              key: ValueKey('now-playing-artist-$artist'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              onPressed: () => onArtistTap(artist),
              child: Text(artist),
            ),
          ),
        );
      }
    }
    children.addAll([
      Text('·', style: secondaryStyle),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          album.trim().isEmpty ? '未知专辑' : album,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: secondaryStyle,
        ),
      ),
    ]);
    return Semantics(
      container: true,
      label: '歌手与专辑',
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 0,
        children: children,
      ),
    );
  }
}
