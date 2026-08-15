import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../library/artwork_view.dart';

Future<void> showTrackInfo(BuildContext context, MediaItem item) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _TrackInfoPanel(item: item),
  );
}

class TrackInfoButton extends StatelessWidget {
  const TrackInfoButton({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '歌曲信息',
    onPressed: () => showTrackInfo(context, item),
    icon: const Icon(Icons.info_outline_rounded),
  );
}

class _TrackInfoPanel extends StatelessWidget {
  const _TrackInfoPanel({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: const Text('歌手'),
            subtitle: Text(
              item.artist?.trim().isNotEmpty == true ? item.artist! : '未知歌手',
            ),
            onTap: () => _showTextDetail(context, '歌手', item.artist ?? '未知歌手'),
          ),
          ListTile(
            leading: const Icon(Icons.album_outlined),
            title: const Text('专辑'),
            subtitle: Text(
              item.album?.trim().isNotEmpty == true ? item.album! : '未知专辑',
            ),
            onTap: () => _showTextDetail(context, '专辑', item.album ?? '未知专辑'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('查看封面大图'),
            onTap: () => _showArtwork(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showTextDetail(BuildContext context, String label, String value) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SelectableText(
                value,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showArtwork(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = math
                  .min(
                    constraints.maxWidth,
                    math.min(constraints.maxHeight, 360),
                  )
                  .toDouble();
              return ArtworkView(
                bytes: item.extras?['artwork'] as Uint8List?,
                size: size,
                borderRadius: 12,
              );
            },
          ),
        ),
      ),
    );
  }
}
