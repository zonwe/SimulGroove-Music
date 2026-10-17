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

@visibleForTesting
String formatLyricSeekTime(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// 同步歌词面板：跟随播放进度滚动并高亮当前行。
///
/// 传入 [onSeek] 后每一行都可点击，并把该行的开始时间回调给播放器；
/// [confirmSeek] 为 true 时先弹出确认对话框，避免误触改变播放进度。
class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.lyrics,
    required this.positionStream,
    required this.initialPosition,
    this.onSeek,
    this.confirmSeek = false,
  });

  final String? lyrics;
  final Stream<Duration> positionStream;
  final Duration initialPosition;
  final ValueChanged<Duration>? onSeek;
  final bool confirmSeek;

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

  Future<void> _seekToLine(LyricLine line) async {
    final onSeek = widget.onSeek;
    if (onSeek == null) return;
    if (widget.confirmSeek) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('跳转到这句歌词？'),
          content: Text('播放进度将定位到 ${formatLyricSeekTime(line.time)}。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('跳转'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    onSeek(line.time);
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
    final canSeek = widget.onSeek != null;
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
            Widget line = AnimatedDefaultTextStyle(
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
            if (canSeek) {
              final seekLine = lines[index];
              line = InkWell(
                onTap: () => _seekToLine(seekLine),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: line,
                ),
              );
            }
            return KeyedSubtree(key: _lineKeys[index], child: line);
          }),
        );
      },
    );
  }
}
