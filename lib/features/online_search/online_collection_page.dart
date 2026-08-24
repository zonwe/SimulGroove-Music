import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/library/artist_names.dart';
import '../../core/online_music/online_music_error.dart';
import '../../core/online_music/online_track.dart';
import '../../core/online_music/online_track_persistence.dart';
import '../player/mini_player_bar.dart';
import '../playlists/playlists_page.dart';
import '../shell/windows_title_bar.dart';
import 'online_artwork_view.dart';
import 'online_track_tile.dart';

enum OnlineCollectionKind { artist, album }

class OnlineCollectionRequest {
  const OnlineCollectionRequest({
    required this.kind,
    required this.value,
    required this.seedTracks,
  });

  final OnlineCollectionKind kind;
  final String value;
  final List<OnlineTrack> seedTracks;
}

class OnlineCollectionPage extends ConsumerStatefulWidget {
  const OnlineCollectionPage({
    required this.request,
    required this.onBack,
    this.standalone = false,
    super.key,
  });

  final OnlineCollectionRequest request;
  final VoidCallback onBack;
  final bool standalone;

  @override
  ConsumerState<OnlineCollectionPage> createState() =>
      _OnlineCollectionPageState();
}

class _OnlineCollectionPageState extends ConsumerState<OnlineCollectionPage> {
  final Set<String> _resolvingTrackIds = {};
  final Set<String> _selectedTrackIds = {};
  late List<OnlineTrack> _tracks;
  String? _refreshMessage;
  var _loading = true;
  var _selectionMode = false;
  var _batchBusy = false;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _tracks = _matchingTracks(widget.request.seedTracks);
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _refreshMessage = null;
    });
    try {
      final result = await ref
          .read(onlineMusicRepositoryProvider)
          .search(widget.request.value);
      if (!mounted || generation != _generation) return;
      final byId = <String, OnlineTrack>{
        for (final track in _tracks) track.id: track,
        for (final track in _matchingTracks(result.items)) track.id: track,
      };
      setState(() {
        _tracks = List.unmodifiable(byId.values);
        _loading = false;
        if (result.partial) {
          _refreshMessage = '部分音乐来源暂时不可用，已显示可用结果。';
        }
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _refreshMessage = _tracks.isEmpty
            ? _errorMessage(error)
            : '暂时无法加载更多歌曲，已保留当前搜索结果。';
      });
    }
  }

  List<OnlineTrack> _matchingTracks(Iterable<OnlineTrack> tracks) {
    final value = widget.request.value.trim().toLowerCase();
    return tracks
        .where((track) {
          if (widget.request.kind == OnlineCollectionKind.album) {
            return track.album.trim().toLowerCase() == value;
          }
          return track.artists
              .expand(splitArtistNames)
              .any((artist) => artist.toLowerCase() == value);
        })
        .toList(growable: false);
  }

  Future<void> _play(OnlineTrack track) async {
    if (_resolvingTrackIds.contains(track.id)) return;
    setState(() => _resolvingTrackIds.add(track.id));
    try {
      await ref.read(onlineTrackPlaybackProvider).play(track);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_errorMessage(error))));
    } finally {
      if (mounted) setState(() => _resolvingTrackIds.remove(track.id));
    }
  }

  void _startSelection() {
    if (_batchBusy) return;
    setState(() => _selectionMode = true);
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
    });
  }

  void _toggleAll() {
    final ids = _tracks.map((track) => track.id).toSet();
    setState(() {
      if (_selectedTrackIds.containsAll(ids)) {
        _selectedTrackIds.clear();
      } else {
        _selectedTrackIds.addAll(ids);
      }
    });
  }

  Future<void> _addSelectedToPlaylist() async {
    if (_batchBusy) return;
    final selected = _tracks
        .where((track) => _selectedTrackIds.contains(track.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final playlists = await ref.read(databaseProvider).watchPlaylists().first;
    if (!mounted) return;
    final choice = await showModalBottomSheet<_PlaylistChoice>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            const ListTile(
              title: Text(
                '添加到歌单',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              minTileHeight: 48,
              leading: const Icon(Icons.playlist_add),
              title: const Text('新建歌单'),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(const _PlaylistChoice.create()),
            ),
            for (final playlist in playlists)
              ListTile(
                minTileHeight: 48,
                leading: const Icon(Icons.queue_music),
                title: Text(playlist.name),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_PlaylistChoice.existing(playlist)),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    String? createdName;
    if (choice.createNew) {
      createdName = await showCreatePlaylistDialog(context);
      if (!mounted || createdName == null || createdName.isEmpty) return;
    }
    setState(() => _batchBusy = true);
    try {
      final database = ref.read(databaseProvider);
      if (choice.createNew) {
        final now = DateTime.now();
        await database.createPlaylistWithTracks(
          PlaylistsCompanion.insert(
            id: const Uuid().v4(),
            name: createdName!,
            accountId: Value(ref.read(accountProvider).value?.id),
            createdAt: now,
            updatedAt: now,
          ),
          selected.map(onlineTrackPlaceholder),
        );
      } else {
        await database.addTracksToPlaylist(
          choice.playlist!.id,
          selected.map(onlineTrackPlaceholder),
        );
      }
      if (!mounted) return;
      final playlistName = createdName ?? choice.playlist!.name;
      _exitSelectionAfterBatch();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('已将 ${selected.length} 首歌曲添加到“$playlistName”'),
          ),
        );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('添加到歌单失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  void _exitSelectionAfterBatch() {
    setState(() {
      _selectionMode = false;
      _selectedTrackIds.clear();
    });
  }

  String _errorMessage(Object error) => switch (error) {
    OnlineMusicException exception => exception.message,
    UnsupportedError exception =>
      exception.message?.toString() ?? '当前平台暂不支持在线播放。',
    _ => '在线歌曲加载失败，请稍后重试。',
  };

  @override
  Widget build(BuildContext context) {
    final showArtwork =
        ref.watch(onlineSearchShowArtworkProvider).value ?? true;
    final playbackSupported = ref.watch(onlineTrackPlaybackProvider).supported;
    final content = SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final headerTextScale =
              (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(1.0, 1.4);
          final expandedHeight =
              (compact ? 276.0 : 312.0) +
              math.max(0, headerTextScale - 1) * (compact ? 128 : 80);
          final firstPlayable = _tracks
              .where((track) => track.playable)
              .firstOrNull;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                automaticallyImplyLeading: false,
                leading: BackButton(
                  onPressed: _selectionMode ? _exitSelection : widget.onBack,
                ),
                title: _CollapsedCollectionTitle(widget.request.value),
                actions: [
                  if (!_selectionMode)
                    IconButton(
                      tooltip: '批量选择',
                      onPressed: _tracks.isEmpty ? null : _startSelection,
                      icon: const Icon(Icons.library_add_check_outlined),
                    )
                  else
                    IconButton(
                      tooltip: '退出批量选择',
                      onPressed: _batchBusy ? null : _exitSelection,
                      icon: const Icon(Icons.close),
                    ),
                  const SizedBox(width: 8),
                ],
                expandedHeight: expandedHeight,
                flexibleSpace: FlexibleSpaceBar(
                  background: _CollectionHeader(
                    request: widget.request,
                    tracks: _tracks,
                    compact: compact,
                    onPlay: firstPlayable == null || _selectionMode
                        ? null
                        : () => _play(firstPlayable),
                  ),
                ),
              ),
              if (_loading)
                const SliverToBoxAdapter(child: LinearProgressIndicator()),
              if (_refreshMessage case final message?)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Material(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline),
                            const SizedBox(width: 10),
                            Expanded(child: Text(message)),
                            if (_tracks.isEmpty)
                              TextButton(
                                onPressed: _loading ? null : _refresh,
                                child: const Text('重试'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_selectionMode)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 16 : 24,
                      12,
                      compact ? 16 : 24,
                      0,
                    ),
                    child: _CollectionSelectionToolbar(
                      selected: _selectedTrackIds.length,
                      total: _tracks.length,
                      busy: _batchBusy,
                      onToggleAll: _toggleAll,
                      onAddToPlaylist: _selectedTrackIds.isEmpty
                          ? null
                          : _addSelectedToPlaylist,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 24,
                    20,
                    compact ? 16 : 24,
                    8,
                  ),
                  child: Text(
                    '歌曲  ${_tracks.length}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (_tracks.isEmpty && !_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyCollection(),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 24,
                    0,
                    compact ? 16 : 24,
                    24,
                  ),
                  sliver: SliverList.separated(
                    itemCount: _tracks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final track = _tracks[index];
                      return OnlineTrackTile(
                        key: ValueKey(track.id),
                        track: track,
                        playbackSupported: playbackSupported,
                        resolving: _resolvingTrackIds.contains(track.id),
                        showArtwork: showArtwork,
                        selectionEnabled: _selectionMode,
                        selected: _selectedTrackIds.contains(track.id),
                        onSelected: _batchBusy
                            ? null
                            : (selected) => _setSelected(track, selected),
                        onPlay: () => _play(track),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
    final backgroundColor = Theme.of(context).colorScheme.surface;
    if (!widget.standalone) {
      return ColoredBox(color: backgroundColor, child: content);
    }
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          const WindowsTitleBar(),
          Expanded(child: content),
        ],
      ),
      bottomNavigationBar: const MiniPlayerBar(),
    );
  }
}

class _PlaylistChoice {
  const _PlaylistChoice.create() : createNew = true, playlist = null;
  const _PlaylistChoice.existing(this.playlist) : createNew = false;

  final bool createNew;
  final Playlist? playlist;
}

class _CollectionSelectionToolbar extends StatelessWidget {
  const _CollectionSelectionToolbar({
    required this.selected,
    required this.total,
    required this.busy,
    required this.onToggleAll,
    required this.onAddToPlaylist,
  });

  final int selected;
  final int total;
  final bool busy;
  final VoidCallback onToggleAll;
  final VoidCallback? onAddToPlaylist;

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
          Text('已选择 $selected 首'),
          OutlinedButton.icon(
            onPressed: busy ? null : onToggleAll,
            icon: Icon(
              selected == total && total > 0
                  ? Icons.deselect
                  : Icons.select_all,
            ),
            label: Text(selected == total && total > 0 ? '取消全选' : '全选'),
          ),
          FilledButton.tonalIcon(
            onPressed: busy ? null : onAddToPlaylist,
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.playlist_add),
            label: const Text('加入歌单'),
          ),
        ],
      ),
    ),
  );
}

class _CollapsedCollectionTitle extends StatelessWidget {
  const _CollapsedCollectionTitle(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final progress =
        settings == null || settings.maxExtent == settings.minExtent
        ? 1.0
        : ((settings.maxExtent - settings.currentExtent) /
                  (settings.maxExtent - settings.minExtent))
              .clamp(0.0, 1.0);
    return Opacity(
      opacity: progress,
      child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({
    required this.request,
    required this.tracks,
    required this.compact,
    required this.onPlay,
  });

  final OnlineCollectionRequest request;
  final List<OnlineTrack> tracks;
  final bool compact;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final artworkTrack = tracks
        .where((track) => track.capabilities.contains('artwork'))
        .firstOrNull;
    final artworkSize = compact ? 124.0 : 164.0;
    final totalDuration = tracks.fold<int>(
      0,
      (total, track) => total + (track.durationMs ?? 0),
    );
    final label = request.kind == OnlineCollectionKind.artist ? '在线歌手' : '在线专辑';
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.4,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 20 : 28,
          72,
          compact ? 20 : 28,
          20,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (artworkTrack == null)
              Container(
                width: artworkSize,
                height: artworkSize,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  request.kind == OnlineCollectionKind.artist
                      ? Icons.person_outline
                      : Icons.album_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              )
            else
              OnlineArtworkView(
                track: artworkTrack,
                size: artworkSize,
                borderRadius: 10,
              ),
            SizedBox(width: compact ? 16 : 24),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    request.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (compact
                                ? Theme.of(context).textTheme.headlineSmall
                                : Theme.of(context).textTheme.headlineMedium)
                            ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _collectionSummary(tracks.length, totalDuration),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onPlay,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('播放第一首'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCollection extends StatelessWidget {
  const _EmptyCollection();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_off_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          Text('没有找到相关歌曲', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    ),
  );
}

String _collectionSummary(int count, int milliseconds) {
  if (milliseconds <= 0) return '$count 首歌曲';
  final duration = Duration(milliseconds: milliseconds);
  final hours = duration.inHours;
  final minutes = math.max(1, duration.inMinutes.remainder(60));
  return hours > 0
      ? '$count 首歌曲 · $hours 小时 $minutes 分钟'
      : '$count 首歌曲 · $minutes 分钟';
}
