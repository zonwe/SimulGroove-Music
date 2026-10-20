import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/online_music/online_music_error.dart';
import '../../core/online_music/online_track.dart';
import '../../core/online_music/online_track_downloader.dart';
import '../../core/online_music/online_track_persistence.dart';
import '../playlists/playlists_page.dart';
import 'online_collection_page.dart';
import 'online_search_controller.dart';
import 'online_search_results.dart';
import 'online_track_context_menu.dart';

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
      _showMessage(message);
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

  Future<void> _loadMore() async {
    if (_batchBusy) return;
    await _controller.loadMore();
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
      _showDownloadMessage(downloader, message, result.warnings);
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

  void _showDownloadMessage(
    OnlineTrackDownloader downloader,
    String message,
    List<OnlineDownloadWarning> warnings,
  ) {
    final retrier = downloader is OnlineDownloadAttachmentRetrier
        ? downloader as OnlineDownloadAttachmentRetrier
        : null;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$message${warnings.isEmpty ? '' : '；${warnings.length} 首歌曲的封面或歌词未完整保存，音频已入库。'}',
          ),
          action: warnings.isEmpty || retrier == null
              ? null
              : SnackBarAction(
                  label: '重试附件',
                  onPressed: () async {
                    try {
                      final remaining = await retrier.retryAttachments(
                        warnings,
                      );
                      if (mounted) {
                        _showDownloadMessage(
                          downloader,
                          remaining.isEmpty ? '封面和歌词已补齐' : '部分附件仍无法保存',
                          remaining,
                        );
                      }
                    } catch (error) {
                      if (mounted) {
                        _showDownloadMessage(
                          downloader,
                          _errorMessage(error),
                          warnings,
                        );
                      }
                    }
                  },
                ),
        ),
      );
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
      _showMessage('已新建歌单“$name”并加入 ${selected.length} 首歌曲');
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
    await showOnlineTrackContextMenu(
      context: context,
      ref: ref,
      track: track,
      tracks: tracks,
      position: position,
      selected: _selectedTrackIds.contains(track.id),
      onToggleSelection: () => _toggleSelectionFromMenu(track),
      onOpenCollection: _openCollection,
      onDownload: (single) => _downloadTracks([single]),
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String message) => _showMessage(message);

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
            12,
            horizontalPadding,
            0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  const SizedBox(height: 12),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => OnlineSearchBody(
                        state: _controller.state,
                        onRetry: _controller.retry,
                        onLoadMore: _loadMore,
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
