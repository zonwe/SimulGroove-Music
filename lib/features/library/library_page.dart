import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/library/scanned_track.dart';
import 'artwork_view.dart';

enum _LibraryView { songs, albums, artists }

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final TextEditingController _search = TextEditingController();
  _LibraryView _view = _LibraryView.songs;
  bool _scanning = false;
  bool _selectionMode = false;
  final Set<String> _selectedTrackIds = <String>{};
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanner = ref.watch(scannerProvider);
    final tracks = ref.watch(tracksProvider);
    final sources = ref.watch(scanSourcesProvider);
    final visibleTracks = _filterTracks(tracks.asData?.value ?? const []);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _selectionMode
              ? _SelectionToolbar(
                  selectedCount: _selectedTrackIds.length,
                  totalCount: visibleTracks.length,
                  onCancel: _clearSelection,
                  onSelectAll: () => setState(
                    () => _selectedTrackIds.addAll(
                      visibleTracks.map((track) => track.id),
                    ),
                  ),
                  onAddToPlaylist: _selectedTrackIds.isEmpty
                      ? null
                      : () => _addSelectedToPlaylist(visibleTracks),
                )
              : Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '音乐库',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (scanner.isSupported)
                      FilledButton.icon(
                        onPressed: _scanning ? null : () => unawaited(_scan()),
                        icon: _scanning
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.library_add_outlined),
                        label: Text(_scanning ? '后台扫描中…' : scanner.actionLabel),
                      ),
                    if (scanner.supportsFullDeviceScan)
                      OutlinedButton.icon(
                        onPressed: _scanning
                            ? null
                            : () => unawaited(_scan(fullDevice: true)),
                        icon: const Icon(Icons.phone_android_outlined),
                        label: const Text('扫描整台设备'),
                      ),
                  ],
                ),
          if (scanner.isSupported) ...[
            const SizedBox(height: 14),
            sources.when(
              loading: () => const LinearProgressIndicator(minHeight: 2),
              error: (error, _) => Text('搜索位置读取失败：$error'),
              data: (values) =>
                  _ScanSources(values: values, onAdd: () => unawaited(_scan())),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索本地歌曲、专辑或艺术家',
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<_LibraryView>(
            segments: const [
              ButtonSegment(
                value: _LibraryView.songs,
                icon: Icon(Icons.music_note),
                label: Text('歌曲'),
              ),
              ButtonSegment(
                value: _LibraryView.albums,
                icon: Icon(Icons.album_outlined),
                label: Text('专辑'),
              ),
              ButtonSegment(
                value: _LibraryView.artists,
                icon: Icon(Icons.people_outline),
                label: Text('艺术家'),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (value) => setState(() => _view = value.first),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: tracks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('音乐库读取失败：$error')),
              data: _buildLibrary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibrary(List<Track> allTracks) {
    final query = _search.text.trim().toLowerCase();
    final tracks = _filterTracks(allTracks);
    if (tracks.isEmpty) {
      return _EmptyLibrary(hasQuery: query.isNotEmpty);
    }
    return switch (_view) {
      _LibraryView.songs => _SongList(
        tracks: tracks,
        selectionMode: _selectionMode,
        selectedTrackIds: _selectedTrackIds,
        onLongPress: _enterSelection,
        onToggleSelected: _toggleSelected,
      ),
      _LibraryView.albums => _GroupGrid(tracks: tracks, byAlbum: true),
      _LibraryView.artists => _GroupGrid(tracks: tracks, byAlbum: false),
    };
  }

  List<Track> _filterTracks(List<Track> allTracks) {
    final query = _search.text.trim().toLowerCase();
    return allTracks
        .where((track) {
          if (query.isEmpty) return true;
          return '${track.title}\n${track.artist}\n${track.album}'
              .toLowerCase()
              .contains(query);
        })
        .toList(growable: false);
  }

  void _enterSelection(Track track) {
    setState(() {
      _selectionMode = true;
      _selectedTrackIds.add(track.id);
    });
  }

  void _toggleSelected(Track track) {
    setState(() {
      if (!_selectedTrackIds.remove(track.id)) {
        _selectedTrackIds.add(track.id);
      }
      if (_selectedTrackIds.isEmpty) _selectionMode = false;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedTrackIds.clear();
    });
  }

  Future<void> _addSelectedToPlaylist(List<Track> visibleTracks) async {
    final selected = visibleTracks
        .where((track) => _selectedTrackIds.contains(track.id))
        .toList(growable: false);
    await _showPlaylistPickerForTracks(context, ref, selected);
    if (mounted) _clearSelection();
  }

  Future<void> _scan({bool fullDevice = false}) async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final scanner = ref.read(scannerProvider);
      final result = fullDevice
          ? await scanner.scanFullDevice()
          : await scanner.scan();
      if (result == null) return;
      final database = ref.read(databaseProvider);
      await database.upsertTracks(result.tracks.map(_toCompanion));
      final now = DateTime.now();
      await database.saveScanSource(
        ScanSourcesCompanion.insert(
          id: const Uuid().v5(Namespace.url.value, result.sourceUri),
          platform: result.tracks.firstOrNull?.sourceType ?? 'unknown',
          uri: result.sourceUri,
          label: result.sourceLabel,
          lastScannedAt: Value(now),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 ${result.tracks.length} 首歌曲')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  TracksCompanion _toCompanion(ScannedTrack track) => TracksCompanion.insert(
    id: track.id,
    sourceType: track.sourceType,
    sourceId: track.sourceId,
    uri: track.uri,
    filePath: Value(track.filePath),
    title: track.title,
    artist: Value(track.artist),
    album: Value(track.album),
    durationMs: Value(track.durationMs),
    artwork: Value(track.artwork),
    lyrics: Value(track.lyrics),
    fileSize: Value(track.fileSize),
    modifiedAt: Value(track.modifiedAt),
    updatedAt: DateTime.now(),
  );
}

class _ScanSources extends StatelessWidget {
  const _ScanSources({required this.values, required this.onAdd});

  final List<ScanSource> values;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: InkWell(
        onTap: () => _showSourceDetails(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.folder_open_outlined, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '搜索位置',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      values.isEmpty ? '尚未指定位置' : '${values.length} 个位置',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSourceDetails(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            ListTile(
              title: const Text(
                '搜索位置',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onAdd();
                },
                icon: const Icon(Icons.add),
                label: const Text('添加位置'),
              ),
            ),
            if (values.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('还没有添加音乐文件夹。'),
              )
            else
              for (final source in values)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(source.label),
                  subtitle: Text(_sourceLocation(source)),
                ),
          ],
        ),
      ),
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.selectedCount,
    required this.totalCount,
    required this.onCancel,
    required this.onSelectAll,
    required this.onAddToPlaylist,
  });

  final int selectedCount;
  final int totalCount;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;
  final VoidCallback? onAddToPlaylist;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        onPressed: onCancel,
        tooltip: '取消选择',
        icon: const Icon(Icons.close),
      ),
      Text('已选择 $selectedCount 首'),
      const Spacer(),
      IconButton(
        onPressed: selectedCount == totalCount || totalCount == 0
            ? null
            : onSelectAll,
        tooltip: '全选',
        icon: const Icon(Icons.select_all),
      ),
      IconButton(
        onPressed: onAddToPlaylist,
        tooltip: '批量加入歌单',
        icon: const Icon(Icons.playlist_add),
      ),
    ],
  );
}

String _sourceLocation(ScanSource source) {
  if (source.uri == 'media-store://external') {
    return 'Android MediaStore · 整台设备';
  }
  if (source.uri.startsWith('content://')) return 'Android 已授权目录';
  return source.uri;
}

class _SongList extends ConsumerWidget {
  const _SongList({
    required this.tracks,
    required this.selectionMode,
    required this.selectedTrackIds,
    required this.onLongPress,
    required this.onToggleSelected,
  });

  final List<Track> tracks;
  final bool selectionMode;
  final Set<String> selectedTrackIds;
  final ValueChanged<Track> onLongPress;
  final ValueChanged<Track> onToggleSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView.separated(
    padding: const EdgeInsets.only(bottom: 18),
    itemCount: tracks.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (context, index) {
      final track = tracks[index];
      return ListTile(
        minTileHeight: 64,
        leading: selectionMode
            ? Checkbox(
                value: selectedTrackIds.contains(track.id),
                onChanged: (_) => onToggleSelected(track),
              )
            : ArtworkView(bytes: track.artwork),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${track.artist} · ${track.album}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _duration(track.durationMs),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (value) {
                if (value == 'playlist') {
                  _showPlaylistPicker(context, ref, track);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'playlist', child: Text('添加到歌单')),
              ],
            ),
          ],
        ),
        onTap: selectionMode
            ? () => onToggleSelected(track)
            : () => ref
                  .read(audioHandlerProvider)
                  .playTracks(tracks, initialIndex: index),
        onLongPress: () => onLongPress(track),
      );
    },
  );
}

class _GroupGrid extends StatelessWidget {
  const _GroupGrid({required this.tracks, required this.byAlbum});

  final List<Track> tracks;
  final bool byAlbum;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Track>>{};
    for (final track in tracks) {
      groups
          .putIfAbsent(byAlbum ? track.album : track.artist, () => [])
          .add(track);
    }
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 18),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 238,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final entry = groups.entries.elementAt(index);
        final first = entry.value.first;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Center(
                      child: ArtworkView(
                        bytes: first.artwork,
                        size: 160,
                        borderRadius: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    entry.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${entry.value.length} 首歌曲',
                    style: Theme.of(context).textTheme.bodySmall,
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

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.library_music_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 14),
        Text(
          hasQuery ? '没有匹配的歌曲' : '音乐库还是空的',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(hasQuery ? '换个关键词试试' : '在 Android 扫描设备音乐，或在 Windows 添加音乐文件夹'),
      ],
    ),
  );
}

String _duration(int? milliseconds) {
  if (milliseconds == null) return '--:--';
  final duration = Duration(milliseconds: milliseconds);
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

Future<void> _showPlaylistPicker(
  BuildContext context,
  WidgetRef ref,
  Track track,
) => _showPlaylistPickerForTracks(context, ref, [track]);

Future<void> _showPlaylistPickerForTracks(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
) async {
  if (tracks.isEmpty) return;
  final playlists = await ref.read(databaseProvider).watchPlaylists().first;
  if (!context.mounted) return;
  if (playlists.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('请先在“歌单”页面新建歌单')));
    return;
  }
  final selected = await showModalBottomSheet<Playlist>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text('添加到歌单', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          for (final playlist in playlists)
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(playlist.name),
              onTap: () => Navigator.of(context).pop(playlist),
            ),
        ],
      ),
    ),
  );
  if (selected == null) return;
  for (final track in tracks) {
    await ref.read(databaseProvider).addTrackToPlaylist(selected.id, track.id);
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已将 ${tracks.length} 首歌曲添加到“${selected.name}”')),
    );
  }
}
