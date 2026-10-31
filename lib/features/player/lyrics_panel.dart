import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/format/duration_text.dart';
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
String formatLyricSeekTime(Duration duration) =>
    formatPlaybackDuration(duration);

/// 开启二次点按确认时，判断这次点按是否只是「选中待确认」的第一次点按。
///
/// 第一次点按某一行只进入待确认状态；再次点按同一行才真正跳转；
/// 点按另一行则把待确认状态移动到新的行。
@visibleForTesting
bool lyricsTapNeedsConfirmation({
  required bool confirmSeek,
  required int? pendingIndex,
  required int tappedIndex,
}) => confirmSeek && pendingIndex != tappedIndex;

/// 同步歌词面板：跟随播放进度滚动并高亮当前行。
///
/// 传入 [onSeek] 后每一行都可点击，并把该行的开始时间回调给播放器；
/// [confirmSeek] 为 true 时使用二次点按确认：第一次点按只选中该行并给出提示，
/// 再次点按同一行才跳转，避免误触改变播放进度，且不打断界面。
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
  int? _pendingSeekIndex;

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
      _pendingSeekIndex = null;
    }
    // 关闭二次确认后不应残留「已选中待确认」的视觉状态。
    if (oldWidget.confirmSeek != widget.confirmSeek && !widget.confirmSeek) {
      _pendingSeekIndex = null;
    }
  }

  void _handleLineTap(int index, LyricLine line) {
    final onSeek = widget.onSeek;
    if (onSeek == null) return;
    if (lyricsTapNeedsConfirmation(
      confirmSeek: widget.confirmSeek,
      pendingIndex: _pendingSeekIndex,
      tappedIndex: index,
    )) {
      setState(() => _pendingSeekIndex = index);
      return;
    }
    setState(() => _pendingSeekIndex = null);
    onSeek(line.time);
  }

  /// 待确认的歌词行：加一圈边框并把「再次点按」的提示放在行内，
  /// 用二次点按代替对话框，避免打断播放界面。
  Widget _buildPendingLine(
    BuildContext context,
    Widget line,
    LyricLine seekLine,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            line,
            const SizedBox(height: 4),
            Text(
              '再次点按跳转到 ${formatLyricSeekTime(seekLine.time)}',
              key: const ValueKey('lyrics-seek-pending-hint'),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  /// 只滚动歌词面板自己的视口，把目标行滚到播放位置对应的对齐处。
  ///
  /// 不能用 [Scrollable.ensureVisible]：它会继续处理所有祖先 Scrollable，
  /// 正在播放页用 [PageView] 承载封面/歌词时，切页动画期间会把整页横向拖走，
  /// 表现为刚滑一点就整页跳过去。这里直接对自己的滚动视口求偏移。
  bool _scrollToLine(
    BuildContext lineContext,
    List<LyricLine> lines,
    int index,
  ) {
    final renderObject = lineContext.findRenderObject();
    if (renderObject == null || !renderObject.attached) return false;
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null || !_scrollController.hasClients) return false;
    final position = _scrollController.position;
    final target = viewport
        .getOffsetToReveal(renderObject, lyricsScrollAlignment(lines, index))
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() >= 0.5) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    return true;
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || scrollTargetIndex >= _lineKeys.length) return;
            // 同一帧内的多次进度回调只滚动一次。
            if (scrollTargetIndex == _lastScrollTargetIndex) return;
            final lineContext = _lineKeys[scrollTargetIndex].currentContext;
            // 目标行尚未布局时先不记录，等下一次进度回调重试。
            if (lineContext == null) return;
            // 面板还没完成布局时不记录，避免之后不再尝试定位。
            if (!_scrollToLine(lineContext, lines, scrollTargetIndex)) return;
            _lastScrollTargetIndex = scrollTargetIndex;
          });
        }
        // 用 Column 一次性构建全部歌词行：ListView 是懒加载的，视口外的行没有
        // Element/RenderObject，GlobalKey.currentContext 为 null，导致切到歌词页
        // 或长歌词滚动时定位拿不到目标行而静默失效。
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
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
                final pending = index == _pendingSeekIndex;
                line = InkWell(
                  onTap: () => _handleLineTap(index, seekLine),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: pending
                        ? _buildPendingLine(context, line, seekLine)
                        : line,
                  ),
                );
              }
              return KeyedSubtree(key: _lineKeys[index], child: line);
            }),
          ),
        );
      },
    );
  }
}
