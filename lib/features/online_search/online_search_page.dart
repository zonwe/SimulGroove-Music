import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/library/artist_names.dart';
import '../../core/online_music/online_music_error.dart';
import '../../core/online_music/online_track.dart';
import '../../core/online_music/online_track_downloader.dart';
import '../../core/online_music/online_track_persistence.dart';
import '../playlists/playlists_page.dart';
import 'online_artwork_view.dart';
import 'online_collection_page.dart';
import 'online_search_controller.dart';
import 'online_track_tile.dart';

class OnlineSearchPage extends ConsumerStatefulWidget {
  const OnlineSearchPage({this.onOpenCollection, super.key});

  final ValueChanged<OnlineCollectionRequest>? onOpenCollection;

  @override
  ConsumerState<OnlineSearchPage> createState() => _OnlineSearchPageState();
}

class _OnlineSearchPageState extends ConsumerState<OnlineSearchPage> {
  late final TextEditingController _query;
  late final OnlineSearchController _controller;
  final Set<String> _resolvingTrackIds = {};
  final Set<String> _selectedTrackIds = {};
  OnlineDownloadProgress? _downloadProgress;
  bool _batchBusy = false;
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(onlineSearchControllerProvider);
    _query = TextEditingController(text: _controller.state.query);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _play(OnlineTrack track) async {
    if (_resolvingTrackIds.contains(track.id)) return;
    setState(() => _resolvingTrackIds.add(track.id));
    try {
      await ref.read(onlineTrackPlaybackProvider).play(track);
    } catch (error) {
      if (!mounted) return;
      final message = switch (error) {
        OnlineMusicException exception => exception.message,
        UnsupportedError exception =>
          exception.message?.toString() ?? '当前平台暂不支持在线播放。',
        _ => '在线播放失败，请稍后重试。',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _resolvingTrackIds.remove(track.id));
    }
  }

  void _queryChanged(String _) {
    if (_selectionMode) _exitSelection();
  }

  void _clearQuery() {
    _query.clear();
    if (_selectionMode) _exitSelection();
    _controller.clear();
  }

  Future<void> _previousPage() async {
    if (_batchBusy) return;
    if (_selectionMode) _exitSelection();
    await _controller.previousPage();
  }

  Future<void> _nextPage() async {
    if (_batchBusy) return;
    if (_selectionMode) _exitSelection();
    await _controller.nextPage();
  }

  void _exitSelection() {
    if (_batchBusy) return;
    setState(() {
      _selectionMode = false;
      _selectedTrackIds.clear();
    });
  }

  void _setSelected(OnlineTrack track, bool selected) {
    setState(() {
      if (selected) {
        _selectedTrackIds.add(track.id);
      } else {
        _selectedTrackIds.remove(track.id);
      }
      _selectionMode = _selectedTrackIds.isNotEmpty;
    });
  }

  void _toggleSelectionFromMenu(OnlineTrack track) {
    if (_batchBusy) return;
    setState(() {
      if (!_selectedTrackIds.add(track.id)) {
        _selectedTrackIds.remove(track.id);
      }
      _selectionMode = _selectedTrackIds.isNotEmpty;
    });
  }

  void _toggleAll(List<OnlineTrack> tracks) {
    final ids = tracks.map((track) => track.id).toSet();
    setState(() {
      if (_selectedTrackIds.containsAll(ids)) {
        _selectedTrackIds.removeAll(ids);
      } else {
        _selectedTrackIds.addAll(ids);
      }
    });
  }

  List<OnlineTrack> _selectedTracks(List<OnlineTrack> tracks) => tracks
      .where((track) => _selectedTrackIds.contains(track.id))
      .toList(growable: false);

  Future<void> _downloadSelected(List<OnlineTrack> tracks) async {
    final selected = _selectedTracks(tracks);
    if (selected.isEmpty) return;
    await _downloadTracks(selected, updateSelection: true);
  }

  Future<void> _downloadTracks(
    List<OnlineTrack> tracks, {
    bool updateSelection = false,
  }) async {
    if (_batchBusy || tracks.isEmpty) return;
    final downloader = ref.read(onlineTrackDownloaderProvider);
    try {
      final destination = await downloader.destination();
      if (!mounted) return;
      if (destination == null) {
        _showError('请先在“设置 > 在线音乐”中选择下载目录。');
        return;
      }
      final downloadDestination = destination;
      setState(() {
        _batchBusy = true;
        _downloadProgress = OnlineDownloadProgress(
          completed: 0,
          total: tracks.length,
        );
      });
      final result = await downloader.downloadAll(
        tracks,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );
      if (!mounted) return;
      if (updateSelection) {
        setState(() {
          _selectedTrackIds.removeAll(
            result.downloaded.map((track) => track.id),
          );
          if (_selectedTrackIds.isEmpty) _selectionMode = false;
        });
      }
      final failed = result.failures.length;
      final message = failed == 0
          ? '已下载 ${result.downloaded.length} 首歌曲到 ${downloadDestination.label}'
          : '下载完成：成功 ${result.downloaded.length} 首，失败 $failed 首。'
                '${_errorMessage(result.failures.first.error)}';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) _showError(_errorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _batchBusy = false;
          _downloadProgress = null;
        });
      }
    }
  }

  Future<void> _createPlaylistFromSelection(List<OnlineTrack> tracks) async {
    if (_batchBusy) return;
    final selected = _selectedTracks(tracks);
    if (selected.isEmpty) return;
    final name = await showCreatePlaylistDialog(context);
    if (!mounted || name == null || name.isEmpty) return;
    setState(() => _batchBusy = true);
    try {
      final now = DateTime.now();
      await ref
          .read(databaseProvider)
          .createPlaylistWithTracks(
            PlaylistsCompanion.insert(
              id: const Uuid().v4(),
              name: name,
              accountId: Value(ref.read(accountProvider).value?.id),
              createdAt: now,
              updatedAt: now,
            ),
            selected.map(onlineTrackPlaceholder),
          );
      if (!mounted) return;
      setState(() {
        _selectionMode = false;
        _selectedTrackIds.clear();
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('已新建歌单“$name”并加入 ${selected.length} 首歌曲')),
        );
    } catch (error) {
      if (mounted) _showError('新建歌单失败：$error');
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Future<void> _showTrackMenu(
    OnlineTrack track,
    List<OnlineTrack> tracks,
    Offset position,
  ) async {
    if (_batchBusy) return;
    final artists = track.artists
        .expand(splitArtistNames)
        .map((artist) => artist.trim())
        .where((artist) => artist.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final selected = _selectedTrackIds.contains(track.id);
    final action = await showMenu<_TrackMenuAction>(
      context: context,
      position: _menuPosition(context, position),
      items: [
        PopupMenuItem(
          value: _TrackMenuAction.artist,
          enabled: artists.isNotEmpty,
          child: _TrackMenuRow(
            icon: Icons.person_outline,
            label: artists.isEmpty ? '未知歌手' : '歌手：${artists.join('、')}',
            submenu: artists.length > 1,
          ),
        ),
        PopupMenuItem(
          value: _TrackMenuAction.album,
          enabled: track.album.trim().isNotEmpty,
          child: _TrackMenuRow(
            icon: Icons.album_outlined,
            label: track.album.trim().isEmpty ? '未知专辑' : '专辑：${track.album}',
          ),
        ),
        PopupMenuItem(
          value: _TrackMenuAction.artwork,
          enabled: track.capabilities.contains('artwork'),
          child: const _TrackMenuRow(icon: Icons.image_outlined, label: '查看封面'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _TrackMenuAction.selection,
          child: _TrackMenuRow(
            icon: selected
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank,
            label: selected ? '取消选中' : '选中',
          ),
        ),
        PopupMenuItem(
          value: _TrackMenuAction.download,
          enabled: ref.read(onlineTrackDownloaderProvider).supported,
          child: const _TrackMenuRow(
            icon: Icons.download_outlined,
            label: '下载单曲',
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _TrackMenuAction.artist:
        final artist = await _chooseArtist(artists, position);
        if (!mounted || artist == null) return;
        _openCollection(
          OnlineCollectionRequest(
            kind: OnlineCollectionKind.artist,
            value: artist,
            seedTracks: tracks,
          ),
        );
      case _TrackMenuAction.album:
        _openCollection(
          OnlineCollectionRequest(
            kind: OnlineCollectionKind.album,
            value: track.album,
            seedTracks: tracks,
          ),
        );
      case _TrackMenuAction.artwork:
        await showOnlineArtworkDialog(context, track);
      case _TrackMenuAction.selection:
        _toggleSelectionFromMenu(track);
      case _TrackMenuAction.download:
        await _downloadTracks([track]);
    }
  }

  Future<String?> _chooseArtist(List<String> artists, Offset position) async {
    if (artists.isEmpty) return null;
    if (artists.length == 1) return artists.single;
    return showMenu<String>(
      context: context,
      position: _menuPosition(context, position + const Offset(12, 12)),
      items: [
        for (final artist in artists)
          PopupMenuItem(
            value: artist,
            child: _TrackMenuRow(icon: Icons.person_outline, label: artist),
          ),
      ],
    );
  }

  void _openCollection(OnlineCollectionRequest request) {
    if (widget.onOpenCollection case final openCollection?) {
      openCollection(request);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => OnlineCollectionPage(
          request: request,
          onBack: () => Navigator.of(routeContext).pop(),
          standalone: true,
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorMessage(Object error) => switch (error) {
    OnlineMusicException exception => exception.message,
    StateError exception => exception.message.toString(),
    _ => '下载失败，请检查网络和目录权限后重试。',
  };

  @override
  Widget build(BuildContext context) {
    final showArtwork =
        ref.watch(onlineSearchShowArtworkProvider).value ?? true;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 24.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            20,
            horizontalPadding,
            0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '在线搜索',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '输入后点击搜索；右键或长按结果可查看歌手、专辑、封面，或选择和下载歌曲。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) =>
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _query,
                          builder: (context, value, _) {
                            final loading =
                                _controller.state.status ==
                                OnlineSearchStatus.loading;
                            return TextField(
                              controller: _query,
                              enabled: !_batchBusy,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                labelText: '歌曲、专辑或艺术家',
                                hintText: '输入关键字后点击搜索',
                                prefixIcon: const Icon(Icons.travel_explore),
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (value.text.isNotEmpty)
                                      IconButton(
                                        tooltip: '清空搜索',
                                        onPressed: _clearQuery,
                                        icon: const Icon(Icons.clear),
                                      ),
                                    IconButton(
                                      tooltip: '立即搜索',
                                      onPressed: loading || _batchBusy
                                          ? null
                                          : () => _controller.searchNow(
                                              _query.text,
                                            ),
                                      icon: loading
                                          ? const SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.search),
                                    ),
                                  ],
                                ),
                              ),
                              onChanged: _queryChanged,
                              onSubmitted: _controller.searchNow,
                            );
                          },
                        ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => _SearchBody(
                        state: _controller.state,
                        onRetry: _controller.retry,
                        onPreviousPage: _previousPage,
                        onNextPage: _nextPage,
                        onPlay: _play,
                        resolvingTrackIds: _resolvingTrackIds,
                        selectedTrackIds: _selectedTrackIds,
                        selectionMode: _selectionMode,
                        batchBusy: _batchBusy,
                        downloadProgress: _downloadProgress,
                        downloadSupported: ref
                            .watch(onlineTrackDownloaderProvider)
                            .supported,
                        showArtwork: showArtwork,
                        onSelected: _setSelected,
                        onContextMenuRequested: _showTrackMenu,
                        onToggleAll: _toggleAll,
                        onExitSelection: _exitSelection,
                        onDownload: _downloadSelected,
                        onCreatePlaylist: _createPlaylistFromSelection,
                        playbackSupported: ref
                            .watch(onlineTrackPlaybackProvider)
                            .supported,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _TrackMenuAction { artist, album, artwork, selection, download }

typedef _TrackContextMenuCallback =
    void Function(OnlineTrack track, List<OnlineTrack> tracks, Offset position);

RelativeRect _menuPosition(BuildContext context, Offset globalPosition) {
  final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
  if (overlay is! RenderBox || !overlay.hasSize) {
    return RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      globalPosition.dx,
      globalPosition.dy,
    );
  }
  final position = overlay.globalToLocal(globalPosition);
  return RelativeRect.fromRect(
    Rect.fromLTWH(position.dx, position.dy, 1, 1),
    Offset.zero & overlay.size,
  );
}

class _TrackMenuRow extends StatelessWidget {
  const _TrackMenuRow({
    required this.icon,
    required this.label,
    this.submenu = false,
  });

  final IconData icon;
  final String label;
  final bool submenu;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Expanded(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      if (submenu) ...[
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right, size: 20),
      ],
    ],
  );
}

class _SearchBody extends StatelessWidget {
  const _SearchBody({
    required this.state,
    required this.onRetry,
    required this.onPreviousPage,
    required this.onNextPage,
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
  });

  final OnlineSearchState state;
  final VoidCallback onRetry;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final ValueChanged<OnlineTrack> onPlay;
  final Set<String> resolvingTrackIds;
  final Set<String> selectedTrackIds;
  final bool selectionMode;
  final bool batchBusy;
  final bool downloadSupported;
  final bool showArtwork;
  final OnlineDownloadProgress? downloadProgress;
  final void Function(OnlineTrack track, bool selected) onSelected;
  final _TrackContextMenuCallback onContextMenuRequested;
  final ValueChanged<List<OnlineTrack>> onToggleAll;
  final VoidCallback onExitSelection;
  final ValueChanged<List<OnlineTrack>> onDownload;
  final ValueChanged<List<OnlineTrack>> onCreatePlaylist;
  final bool playbackSupported;

  @override
  Widget build(BuildContext context) => switch (state.status) {
    OnlineSearchStatus.idle => const _SearchMessage(
      icon: Icons.manage_search_rounded,
      title: '输入关键字后点击搜索',
      message: '需要先在账号页登录，并由服务端启用允许的音乐来源。',
    ),
    OnlineSearchStatus.loading => const _LoadingState(),
    OnlineSearchStatus.empty => _SearchMessage(
      icon: Icons.search_off_rounded,
      title: '没有找到相关结果',
      message: '可以尝试歌曲原名、艺术家名称，或减少关键字后重新搜索。',
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('重新搜索'),
      ),
    ),
    OnlineSearchStatus.error => _SearchMessage(
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
      onPreviousPage: onPreviousPage,
      onNextPage: onNextPage,
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
      onPreviousPage: onPreviousPage,
      onNextPage: onNextPage,
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
    required this.onPreviousPage,
    required this.onNextPage,
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
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final ValueChanged<OnlineTrack> onPlay;
  final Set<String> resolvingTrackIds;
  final Set<String> selectedTrackIds;
  final bool selectionMode;
  final bool batchBusy;
  final bool downloadSupported;
  final bool showArtwork;
  final OnlineDownloadProgress? downloadProgress;
  final void Function(OnlineTrack track, bool selected) onSelected;
  final _TrackContextMenuCallback onContextMenuRequested;
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
    return SingleChildScrollView(
      key: PageStorageKey<String>(
        'online-search-results-${state.query}-${state.page}',
      ),
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
          if (state.hasPreviousPage ||
              state.hasNextPage ||
              state.isPageLoading ||
              state.pageMessage != null) ...[
            const SizedBox(height: 10),
            _PaginationBar(
              page: state.page,
              hasPreviousPage: state.hasPreviousPage,
              hasNextPage: state.hasNextPage,
              loading: state.isPageLoading,
              enabled: !batchBusy,
              message: state.pageMessage,
              messageIsError: state.pageMessageIsError,
              onPreviousPage: onPreviousPage,
              onNextPage: onNextPage,
            ),
          ],
        ],
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.hasPreviousPage,
    required this.hasNextPage,
    required this.loading,
    required this.enabled,
    required this.onPreviousPage,
    required this.onNextPage,
    this.message,
    this.messageIsError = false,
  });

  final int page;
  final bool hasPreviousPage;
  final bool hasNextPage;
  final bool loading;
  final bool enabled;
  final String? message;
  final bool messageIsError;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;

  @override
  Widget build(BuildContext context) {
    final controlsEnabled = enabled && !loading;
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
    );
    return Semantics(
      container: true,
      liveRegion: loading || message != null,
      label: loading ? '正在加载其他页搜索结果' : '搜索结果第 $page 页',
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: buttonStyle,
                    onPressed: controlsEnabled && hasPreviousPage
                        ? onPreviousPage
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                    label: const Text('上一页'),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 76),
                    child: Text(
                      '第 $page 页',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: controlsEnabled && hasNextPage
                        ? onNextPage
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    label: const Text('下一页'),
                  ),
                ],
              ),
              if (loading) ...[
                const SizedBox(height: 8),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('正在翻页…'),
                  ],
                ),
              ],
              if (message case final message?) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: messageIsError
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
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

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
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
