import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../library/artwork_view.dart';
import 'lyrics_panel.dart';

const _pageTransitionDuration = Duration(milliseconds: 280);

/// 经典播放布局的封面/歌词分页：一屏只显示一页，左右滑动切换。
///
/// 关闭“点击歌词定位播放进度”时（[onSeek] 为 null），点按歌词页任意位置都能切回封面；
/// 开启定位时歌词行需要自己消费点按，此时只保留滑动切回，避免定位点按被当成切页。
/// 封面页始终可以点按进入歌词页，保留原来的点按入口。
class NowPlayingArtworkLyricsPager extends StatefulWidget {
  const NowPlayingArtworkLyricsPager({
    super.key,
    required this.item,
    required this.positionStream,
    required this.initialPosition,
    this.onSeek,
    this.confirmSeek = false,
  });

  final MediaItem item;
  final Stream<Duration> positionStream;
  final Duration initialPosition;
  final ValueChanged<Duration>? onSeek;
  final bool confirmSeek;

  @override
  State<NowPlayingArtworkLyricsPager> createState() =>
      _NowPlayingArtworkLyricsPagerState();
}

class _NowPlayingArtworkLyricsPagerState
    extends State<NowPlayingArtworkLyricsPager> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    if (page == _page) return;
    setState(() => _page = page);
    if (!_controller.hasClients) return;
    _controller.animateToPage(
      page,
      duration: _pageTransitionDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canTapLyricsToSwitch = widget.onSeek == null;
    // PageView 默认不接受鼠标拖动；补上鼠标，桌面端经典布局也能用拖动切页。
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
      child: PageView(
        controller: _controller,
        onPageChanged: (page) {
          if (page != _page) setState(() => _page = page);
        },
        children: <Widget>[
          GestureDetector(
            key: const ValueKey('now-playing-cover-page'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _goToPage(1),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest.shortestSide.clamp(
                  180.0,
                  320.0,
                );
                return Center(
                  child: ArtworkView(
                    key: const ValueKey('cover'),
                    bytes: widget.item.extras?['artwork'] as Uint8List?,
                    size: size,
                    borderRadius: 12,
                  ),
                );
              },
            ),
          ),
          GestureDetector(
            key: const ValueKey('now-playing-lyrics-page'),
            behavior: HitTestBehavior.opaque,
            onTap: canTapLyricsToSwitch ? () => _goToPage(0) : null,
            child: LyricsPanel(
              lyrics: widget.item.extras?['lyrics'] as String?,
              positionStream: widget.positionStream,
              initialPosition: widget.initialPosition,
              onSeek: widget.onSeek,
              confirmSeek: widget.confirmSeek,
            ),
          ),
        ],
      ),
    );
  }
}
