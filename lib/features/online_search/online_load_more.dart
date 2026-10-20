import 'package:flutter/material.dart';

/// 滚动接近底部时触发加载更多的监听器。
///
/// 只负责“什么时候该加载”，是否真的还有下一页由调用方判断，
/// 因此重复触发是安全的。加载会在 [ScrollMetricsNotification] 或滚动通知
/// 中直接回调：前者由滚动位置在帧结束后以微任务派发，后者发生在手势
/// 或惯性滚动过程中，都不会与构建阶段冲突。
class OnlineLoadMoreListener extends StatefulWidget {
  const OnlineLoadMoreListener({
    super.key,
    required this.child,
    required this.onLoadMore,
    this.threshold = 320,
  });

  final Widget child;
  final VoidCallback onLoadMore;

  /// 距底部还有多少像素时开始加载下一页。
  final double threshold;

  @override
  State<OnlineLoadMoreListener> createState() => _OnlineLoadMoreListenerState();
}

class _OnlineLoadMoreListenerState extends State<OnlineLoadMoreListener> {
  void _handleMetrics(ScrollMetrics metrics) {
    if (metrics.extentAfter > widget.threshold) return;
    widget.onLoadMore();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          _handleMetrics(notification.metrics);
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification ||
                notification is ScrollEndNotification) {
              _handleMetrics(notification.metrics);
            }
            return false;
          },
          child: widget.child,
        ),
      );
}

/// 列表底部的“加载更多 / 到底了”提示条。
class OnlineLoadMoreFooter extends StatelessWidget {
  const OnlineLoadMoreFooter({
    super.key,
    required this.hasMore,
    required this.loading,
    required this.onLoadMore,
    this.message,
    this.messageIsError = false,
    this.endLabel,
    this.loadingLabel = '正在加载更多…',
  });

  final bool hasMore;
  final bool loading;
  final VoidCallback onLoadMore;

  /// 加载失败或来源降级时的提示；优先于按钮和到底提示显示。
  final String? message;
  final bool messageIsError;

  /// 没有更多结果时的提示；为空则不显示。
  final String? endLabel;
  final String loadingLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return _FooterShell(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(loadingLabel),
          ],
        ),
      );
    }
    if (message case final message?) {
      return _FooterShell(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: messageIsError
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (hasMore) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: onLoadMore,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试加载'),
              ),
            ],
          ],
        ),
      );
    }
    if (hasMore) {
      return _FooterShell(
        child: TextButton.icon(
          onPressed: onLoadMore,
          icon: const Icon(Icons.expand_more_rounded),
          label: const Text('加载更多'),
        ),
      );
    }
    if (endLabel case final endLabel?) {
      return _FooterShell(
        child: Text(
          endLabel,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _FooterShell extends StatelessWidget {
  const _FooterShell({required this.child, this.liveRegion = false});

  final Widget child;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: liveRegion,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(child: child),
    ),
  );
}
