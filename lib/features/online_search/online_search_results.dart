import 'package:flutter/material.dart';

import '../../core/online_music/online_track_downloader.dart';
import '../../core/online_music/online_track.dart';
import 'online_load_more.dart';
import 'online_search_controller.dart';
import 'online_track_tile.dart';

typedef OnlineTrackContextMenuCallback =
    void Function(OnlineTrack track, List<OnlineTrack> tracks, Offset position);

/// 搜索结果主体：按控制器状态渲染空闲/加载/空/错误/数据各分支。
class OnlineSearchBody extends StatelessWidget {
  const OnlineSearchBody({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onLoadMore,
    required this.onPlay,
    required this.resolvingTrackIds,
    required this.selectedTrackIds,
    required this.selectionMode,
    required this.batchBusy,
    required this.downloadSupported,
    required this.showArtwork,
    required this.onSelected,
    required this.onContextMenuRequested,
    required this.onToggleAll,
    required this.onExitSelection,
    required this.onDownload,
    required this.onCreatePlaylist,
    required this.playbackSupported,
    this.downloadProgress,
  });

  final OnlineSearchState state;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final ValueChanged<OnlineTrack> onPlay;
  final Set<String> resolvingTrackIds;
  final Set<String> selectedTrackIds;
  final bool selectionMode;
  final bool batchBusy;
  final bool downloadSupported;
  final bool showArtwork;
  final OnlineDownloadProgress? downloadProgress;
  final void Function(OnlineTrack track, bool selected) onSelected;
  final OnlineTrackContextMenuCallback onContextMenuRequested;
  final ValueChanged<List<OnlineTrack>> onToggleAll;
  final VoidCallback onExitSelection;
  final ValueChanged<List<OnlineTrack>> onDownload;
  final ValueChanged<List<OnlineTrack>> onCreatePlaylist;
  final bool playbackSupported;

  @override
  Widget build(BuildContext context) => switch (state.status) {
    OnlineSearchStatus.idle => const OnlineSearchMessage(
      icon: Icons.manage_search_rounded,
      title: '输入关键字后点击搜索',
      message: '需要先在账号页登录，并由服务端启用允许的音乐来源。',
    ),
    OnlineSearchStatus.loading => const _LoadingState(),
    OnlineSearchStatus.empty => OnlineSearchMessage(
      icon: Icons.search_off_rounded,
      title: '没有找到相关结果',
      message: '可以尝试歌曲原名、艺术家名称，或减少关键字后重新搜索。',
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('重新搜索'),
      ),
    ),
    OnlineSearchStatus.error => OnlineSearchMessage(
      icon: Icons.cloud_off_outlined,
      title: '在线搜索失败',
      message: state.message ?? '在线音乐服务暂时不可用。',
      liveRegion: true,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('重试'),
      ),
    ),
    OnlineSearchStatus.data => _ResultsList(
      state: state,
      onLoadMore: onLoadMore,
      onPlay: onPlay,
      resolvingTrackIds: resolvingTrackIds,
      selectedTrackIds: selectedTrackIds,
      selectionMode: selectionMode,
      batchBusy: batchBusy,
      downloadSupported: downloadSupported,
      showArtwork: showArtwork,
      downloadProgress: downloadProgress,
      onSelected: onSelected,
      onContextMenuRequested: onContextMenuRequested,
      onToggleAll: onToggleAll,
      onExitSelection: onExitSelection,
      onDownload: onDownload,
      onCreatePlaylist: onCreatePlaylist,
      playbackSupported: playbackSupported,
    ),
    OnlineSearchStatus.partial => _ResultsList(
      state: state,
      partial: true,
      onLoadMore: onLoadMore,
      onPlay: onPlay,
      resolvingTrackIds: resolvingTrackIds,
      selectedTrackIds: selectedTrackIds,
      selectionMode: selectionMode,
      batchBusy: batchBusy,
      downloadSupported: downloadSupported,
      showArtwork: showArtwork,
      downloadProgress: downloadProgress,
      onSelected: onSelected,
      onContextMenuRequested: onContextMenuRequested,
      onToggleAll: onToggleAll,
      onExitSelection: onExitSelection,
      onDownload: onDownload,
      onCreatePlaylist: onCreatePlaylist,
      playbackSupported: playbackSupported,
    ),
  };
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: '正在搜索在线音乐',
    child: const Column(
      children: [
        LinearProgressIndicator(),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在搜索多个音乐来源…'),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.state,
    required this.onLoadMore,
    required this.onPlay,
    required this.resolvingTrackIds,
    required this.selectedTrackIds,
    required this.selectionMode,
    required this.batchBusy,
    required this.downloadSupported,
    required this.showArtwork,
    required this.onSelected,
    required this.onContextMenuRequested,
    required this.onToggleAll,
    required this.onExitSelection,
    required this.onDownload,
    required this.onCreatePlaylist,
    this.downloadProgress,
    required this.playbackSupported,
    this.partial = false,
  });

  final OnlineSearchState state;
  final bool partial;
  final VoidCallback onLoadMore;
  final ValueChanged<OnlineTrack> onPlay;
  final Set<String> resolvingTrackIds;
  final Set<String> selectedTrackIds;
  final bool selectionMode;
  final bool batchBusy;
  final bool downloadSupported;
  final bool showArtwork;
  final OnlineDownloadProgress? downloadProgress;
  final void Function(OnlineTrack track, bool selected) onSelected;
  final OnlineTrackContextMenuCallback onContextMenuRequested;
  final ValueChanged<List<OnlineTrack>> onToggleAll;
  final VoidCallback onExitSelection;
  final ValueChanged<List<OnlineTrack>> onDownload;
  final ValueChanged<List<OnlineTrack>> onCreatePlaylist;
  final bool playbackSupported;

  @override
  Widget build(BuildContext context) {
    final selectedCount = state.items
        .where((track) => selectedTrackIds.contains(track.id))
        .length;
    final providers = state.warnings
        .map((warning) => warning.provider)
        .toSet()
        .join('、');
    return OnlineLoadMoreListener(
      onLoadMore: onLoadMore,
      child: SingleChildScrollView(
        key: PageStorageKey<String>('online-search-results-${state.query}'),
        padding: const EdgeInsetsDirectional.only(end: 16, bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selectionMode)
              _SelectionToolbar(
                total: state.items.length,
                selected: selectedCount,
                busy: batchBusy,
                downloadSupported: downloadSupported,
                onToggleAll: () => onToggleAll(state.items),
                onExitSelection: onExitSelection,
                onDownload: () => onDownload(state.items),
                onCreatePlaylist: () => onCreatePlaylist(state.items),
              ),
            if (downloadProgress case final progress?) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                label: progress.currentTrackId == null
                    ? '已完成 ${progress.completed} 首，共 ${progress.total} 首'
                    : '正在下载，第 ${progress.completed + 1} 首，共 ${progress.total} 首',
                child: LinearProgressIndicator(
                  value: progress.total == 0
                      ? null
                      : progress.completed / progress.total,
                ),
              ),
            ],
            if (selectionMode || downloadProgress != null)
              const SizedBox(height: 10),
            if (partial) ...[
              Semantics(
                liveRegion: true,
                child: Material(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            providers.isEmpty
                                ? '部分来源暂时不可用，已显示其余搜索结果。'
                                : '$providers 暂时不可用，已显示其余搜索结果。',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            for (final track in state.items) ...[
              OnlineTrackTile(
                key: ValueKey(track.id),
                track: track,
                playbackSupported: playbackSupported,
                resolving: resolvingTrackIds.contains(track.id),
                selected: selectedTrackIds.contains(track.id),
                selectionEnabled: selectionMode,
                showArtwork: showArtwork,
                onContextMenuRequested: (position) =>
                    onContextMenuRequested(track, state.items, position),
                onSelected: batchBusy
                    ? null
                    : (selected) => onSelected(track, selected),
                onPlay: () => onPlay(track),
              ),
              const SizedBox(height: 6),
            ],
            OnlineLoadMoreFooter(
              hasMore: state.hasMore,
              loading: state.isLoadingMore,
              onLoadMore: onLoadMore,
              message: state.loadMoreMessage,
              messageIsError: state.loadMoreMessageIsError,
              endLabel: '已经到底啦 · 共 ${state.items.length} 首',
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.total,
    required this.selected,
    required this.busy,
    required this.downloadSupported,
    required this.onToggleAll,
    required this.onExitSelection,
    required this.onDownload,
    required this.onCreatePlaylist,
  });

  final int total;
  final int selected;
  final bool busy;
  final bool downloadSupported;
  final VoidCallback onToggleAll;
  final VoidCallback onExitSelection;
  final VoidCallback onDownload;
  final VoidCallback onCreatePlaylist;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: '退出批量选择',
            onPressed: busy ? null : onExitSelection,
            icon: const Icon(Icons.close_rounded),
          ),
          const Text('批量选择'),
          TextButton.icon(
            onPressed: busy ? null : onToggleAll,
            icon: Icon(
              selected == total
                  ? Icons.deselect_rounded
                  : Icons.select_all_rounded,
            ),
            label: Text(selected == total ? '取消全选' : '全选'),
          ),
          Semantics(liveRegion: true, child: Text('已选 $selected / $total 首')),
          if (downloadSupported)
            FilledButton.tonalIcon(
              onPressed: selected == 0 || busy ? null : onDownload,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(selected == 0 ? '批量下载' : '下载 $selected 首'),
            ),
          FilledButton.icon(
            onPressed: selected == 0 || busy ? null : onCreatePlaylist,
            icon: const Icon(Icons.playlist_add_rounded),
            label: const Text('加入新歌单'),
          ),
        ],
      ),
    ),
  );
}

/// 搜索页非数据状态（空闲/空/错误）的统一展示。
class OnlineSearchMessage extends StatelessWidget {
  const OnlineSearchMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.liveRegion = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: liveRegion,
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 58,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (action case final action?) ...[
                const SizedBox(height: 18),
                action,
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
