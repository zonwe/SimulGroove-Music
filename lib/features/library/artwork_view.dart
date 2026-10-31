import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

class ArtworkView extends StatelessWidget {
  const ArtworkView({
    super.key,
    required this.bytes,
    this.size = 48,
    this.borderRadius = 8,
  });

  final Uint8List? bytes;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    // 扫描时封面已压到 320px，但列表项只要 48–160 逻辑像素。按显示尺寸解码，
    // 避免为每个列表项保留一张 320×320 的位图（每张约 410 KB）。
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = (size * devicePixelRatio).round().clamp(1, 1024);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.square(
        dimension: size,
        child: bytes == null || bytes!.isEmpty
            ? ColoredBox(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(Icons.music_note_rounded, size: size * 0.42),
              )
            : Image.memory(
                bytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: decodeWidth,
              ),
      ),
    );
  }
}

/// 按曲目 id 取封面的列表封面。
///
/// 封面已从 `Tracks` 拆到 `track_artworks`，列表查询不再携带 blob；这里只用
/// 可见行的 id 单独取图，行滚出屏幕后订阅随之释放。
class TrackArtworkView extends ConsumerWidget {
  const TrackArtworkView({
    super.key,
    required this.trackId,
    this.bytes,
    this.size = 48,
    this.borderRadius = 8,
  });

  /// 为 null 时直接显示占位图（例如空歌单）。
  final String? trackId;

  /// 已经拿到封面时（在线曲目或已缓存的队列项）优先使用，省一次查询。
  final Uint8List? bytes;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = trackId;
    final resolved =
        bytes ??
        (id == null ? null : ref.watch(trackArtworkProvider(id)).value);
    return ArtworkView(bytes: resolved, size: size, borderRadius: borderRadius);
  }
}
