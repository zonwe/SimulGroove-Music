import 'package:flutter/material.dart';

import '../../core/lyrics/lrc_parser.dart';

@visibleForTesting
int lyricsScrollTargetIndex(List<LyricLine> lines, int currentIndex) {
  if (currentIndex < 0) return currentIndex;
  final lastTextIndex = lines.lastIndexWhere((line) => line.text.isNotEmpty);
  if (lastTextIndex >= 0 && currentIndex >= lastTextIndex) {
    return lastTextIndex;
  }
  return currentIndex;
}

@visibleForTesting
double lyricsScrollAlignment(List<LyricLine> lines, int targetIndex) {
  final lastTextIndex = lines.lastIndexWhere((line) => line.text.isNotEmpty);
  return targetIndex >= 0 && targetIndex == lastTextIndex ? 1 : 0.5;
}

/// 同步歌词面板：跟随播放进度滚动并高亮当前行。
class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.lyrics,
    required this.positionStream,
    required this.initialPosition,
  });

  final String? lyrics;
  final Stream<Duration> positionStream;
  final Duration initialPosition;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  final List<GlobalKey> _lineKeys = <GlobalKey>[];
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );
  int? _lastScrollTargetIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _lineKeys.clear();
      _lastScrollTargetIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = parseLrc(widget.lyrics);
    if (lines.isEmpty) {
      return const Center(key: ValueKey('lyrics-empty'), child: Text('暂无同步歌词'));
    }
    if (_lineKeys.length != lines.length) {
      _lineKeys
        ..clear()
        ..addAll(List<GlobalKey>.generate(lines.length, (_) => GlobalKey()));
    }
    return StreamBuilder<Duration>(
      key: const ValueKey('lyrics'),
      stream: widget.positionStream,
      initialData: widget.initialPosition,
      builder: (context, snapshot) {
        final current = lyricAt(lines, snapshot.data ?? Duration.zero);
        final currentIndex = current == null ? -1 : lines.indexOf(current);
        final scrollTargetIndex = lyricsScrollTargetIndex(lines, currentIndex);
        if (scrollTargetIndex >= 0 &&
            scrollTargetIndex != _lastScrollTargetIndex) {
          _lastScrollTargetIndex = scrollTargetIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || scrollTargetIndex >= _lineKeys.length) return;
            final lineContext = _lineKeys[scrollTargetIndex].currentContext;
            if (lineContext != null) {
              Scrollable.ensureVisible(
                lineContext,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: lyricsScrollAlignment(lines, scrollTargetIndex),
              );
            }
          });
        }
        // Build all lines so a distant current line has a context on the first
        // frame and can be centered immediately when the cover is switched.
        return ListView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 32),
          children: List<Widget>.generate(lines.length, (index) {
            final selected = index == currentIndex;
            return AnimatedDefaultTextStyle(
              key: _lineKeys[index],
              duration: const Duration(milliseconds: 180),
              style:
                  (selected
                          ? Theme.of(context).textTheme.titleLarge
                          : Theme.of(context).textTheme.bodyLarge)!
                      .copyWith(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: selected
                            ? FontWeight.w500
                            : FontWeight.w400,
                        height: 1.8,
                      ),
              child: Text(lines[index].text, textAlign: TextAlign.center),
            );
          }),
        );
      },
    );
  }
}
