import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/library/artist_names.dart';
import '../../core/online_music/online_track.dart';
import 'online_artwork_view.dart';
import 'online_collection_page.dart';

/// 右键/长按菜单的动作语义。
enum OnlineTrackMenuAction { artist, album, artwork, selection, download }

/// 菜单条目行。
class OnlineTrackMenuRow extends StatelessWidget {
  const OnlineTrackMenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.submenu = false,
  });

  final IconData icon;
  final String label;
  final bool submenu;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Expanded(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      if (submenu) ...[
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right, size: 20),
      ],
    ],
  );
}

RelativeRect menuPosition(BuildContext context, Offset globalPosition) {
  final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
  if (overlay is! RenderBox || !overlay.hasSize) {
    return RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      globalPosition.dx,
      globalPosition.dy,
    );
  }
  final position = overlay.globalToLocal(globalPosition);
  return RelativeRect.fromRect(
    Rect.fromLTWH(position.dx, position.dy, 1, 1),
    Offset.zero & overlay.size,
  );
}

/// 展示在线曲目的右键/长按菜单并处理选中动作。
///
/// 动作通过回调交还调用方：合集导航、选中切换与单曲下载都依赖页面状态。
Future<void> showOnlineTrackContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required OnlineTrack track,
  required List<OnlineTrack> tracks,
  required Offset position,
  required bool selected,
  required VoidCallback onToggleSelection,
  required void Function(OnlineCollectionRequest request) onOpenCollection,
  required Future<void> Function(OnlineTrack track) onDownload,
}) async {
  final artists = track.artists
      .expand(splitArtistNames)
      .map((artist) => artist.trim())
      .where((artist) => artist.isNotEmpty)
      .toSet()
      .toList(growable: false);
  final action = await showMenu<OnlineTrackMenuAction>(
    context: context,
    position: menuPosition(context, position),
    items: [
      PopupMenuItem(
        value: OnlineTrackMenuAction.artist,
        enabled: artists.isNotEmpty,
        child: OnlineTrackMenuRow(
          icon: Icons.person_outline,
          label: artists.isEmpty ? '未知歌手' : '歌手：${artists.join('、')}',
          submenu: artists.length > 1,
        ),
      ),
      PopupMenuItem(
        value: OnlineTrackMenuAction.album,
        enabled: track.album.trim().isNotEmpty,
        child: OnlineTrackMenuRow(
          icon: Icons.album_outlined,
          label: track.album.trim().isEmpty ? '未知专辑' : '专辑：${track.album}',
        ),
      ),
      PopupMenuItem(
        value: OnlineTrackMenuAction.artwork,
        enabled: track.capabilities.contains('artwork'),
        child: const OnlineTrackMenuRow(
          icon: Icons.image_outlined,
          label: '查看封面',
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: OnlineTrackMenuAction.selection,
        child: OnlineTrackMenuRow(
          icon: selected
              ? Icons.check_box_outlined
              : Icons.check_box_outline_blank,
          label: selected ? '取消选中' : '选中',
        ),
      ),
      PopupMenuItem(
        value: OnlineTrackMenuAction.download,
        enabled: ref.read(onlineTrackDownloaderProvider).supported,
        child: const OnlineTrackMenuRow(
          icon: Icons.download_outlined,
          label: '下载单曲',
        ),
      ),
    ],
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case OnlineTrackMenuAction.artist:
      final artist = await _chooseArtist(context, artists, position);
      if (!context.mounted || artist == null) return;
      onOpenCollection(
        OnlineCollectionRequest(
          kind: OnlineCollectionKind.artist,
          value: artist,
          seedTracks: tracks,
        ),
      );
    case OnlineTrackMenuAction.album:
      onOpenCollection(
        OnlineCollectionRequest(
          kind: OnlineCollectionKind.album,
          value: track.album,
          seedTracks: tracks,
        ),
      );
    case OnlineTrackMenuAction.artwork:
      await showOnlineArtworkDialog(context, track);
    case OnlineTrackMenuAction.selection:
      onToggleSelection();
    case OnlineTrackMenuAction.download:
      await onDownload(track);
  }
}

Future<String?> _chooseArtist(
  BuildContext context,
  List<String> artists,
  Offset position,
) async {
  if (artists.isEmpty) return null;
  if (artists.length == 1) return artists.single;
  return showMenu<String>(
    context: context,
    position: menuPosition(context, position + const Offset(12, 12)),
    items: [
      for (final artist in artists)
        PopupMenuItem(
          value: artist,
          child: OnlineTrackMenuRow(icon: Icons.person_outline, label: artist),
        ),
    ],
  );
}
