import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/player/now_playing_layout.dart';
import '../library/artwork_view.dart';
import 'lyrics_panel.dart';

/// 双栏布局仅在桌面端且宽度充足时启用。
bool shouldUseSplitNowPlayingLayout({
  required NowPlayingLayout layout,
  required TargetPlatform platform,
  required bool isWeb,
  required double availableWidth,
}) =>
    layout == NowPlayingLayout.split &&
    !isWeb &&
    (platform == TargetPlatform.windows || platform == TargetPlatform.linux) &&
    availableWidth >= 900;

/// 播放界面双栏模式：左侧封面、右侧歌词。
class NowPlayingSplitArtworkLyrics extends StatelessWidget {
  const NowPlayingSplitArtworkLyrics({
    super.key,
    required this.item,
    required this.positionStream,
    required this.initialPosition,
  });

  final MediaItem item;
  final Stream<Duration> positionStream;
  final Duration initialPosition;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gap = constraints.maxWidth < 1100 ? 28.0 : 48.0;
      final coverSpace = (constraints.maxWidth - gap) * 0.44;
      final coverSize = math
          .min(math.min(coverSpace, constraints.maxHeight), 400.0)
          .clamp(0.0, 400.0);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 9,
            child: Center(
              child: ArtworkView(
                key: ValueKey(('split-cover', item.id)),
                bytes: item.extras?['artwork'] as Uint8List?,
                size: coverSize,
                borderRadius: 14,
              ),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            flex: 11,
            child: LyricsPanel(
              key: ValueKey(('split-lyrics', item.id)),
              lyrics: item.extras?['lyrics'] as String?,
              positionStream: positionStream,
              initialPosition: initialPosition,
            ),
          ),
        ],
      );
    },
  );
}
