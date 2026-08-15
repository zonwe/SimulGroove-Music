import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/online_music/online_track.dart';

class OnlineArtworkView extends ConsumerWidget {
  const OnlineArtworkView({
    required this.track,
    this.size = 48,
    this.borderRadius = 8,
    super.key,
  });

  final OnlineTrack track;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = track.capabilities.contains('artwork')
        ? ref.watch(onlineTrackArtworkProvider(track))
        : null;
    return _ArtworkFrame(
      artwork: artwork,
      title: track.title,
      size: size,
      borderRadius: borderRadius,
    );
  }
}

Future<void> showOnlineArtworkDialog(BuildContext context, OnlineTrack track) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final mediaSize = MediaQuery.sizeOf(dialogContext);
        final artworkSize = math
            .min(520.0, math.min(mediaSize.width - 64, mediaSize.height - 180))
            .clamp(160.0, 520.0);
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(dialogContext).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭封面',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: OnlineArtworkView(
                      track: track,
                      size: artworkSize,
                      borderRadius: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

class _ArtworkFrame extends StatelessWidget {
  const _ArtworkFrame({
    required this.artwork,
    required this.title,
    required this.size,
    required this.borderRadius,
  });

  final AsyncValue<Uint8List?>? artwork;
  final String title;
  final double size;
  final double borderRadius;

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
        size: math.min(32, size * 0.5),
      ),
    );
    final cacheSize = math.max(96, (size * 2).round());
    final child = artwork?.when(
      data: (bytes) => bytes == null
          ? fallback
          : Image.memory(
              bytes,
              fit: BoxFit.cover,
              cacheWidth: cacheSize,
              cacheHeight: cacheSize,
              gaplessPlayback: true,
              semanticLabel: '$title 封面',
              errorBuilder: (_, _, _) => fallback,
            ),
      loading: () => ColoredBox(
        color: colorScheme.secondaryContainer,
        child: Center(
          child: SizedBox.square(
            dimension: math.min(24, size * 0.4),
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
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.square(dimension: size, child: child ?? fallback),
    );
  }
}
