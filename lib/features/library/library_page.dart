import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/library/artist_names.dart';
import '../../core/library/library_track_filter.dart';
import '../../core/player/track_directory.dart';
import 'artwork_view.dart';
import 'collection_page.dart';
import '../player/playback_navigation.dart';

enum _LibraryView { songs, albums, artists }

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final TextEditingController _search = TextEditingController();
  final _trackFilter = LibraryTrackFilter();
  _LibraryView _view = _LibraryView.songs;
  bool _selectionMode = false;
  final Set<String> _selectedTrackIds = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(tracksProvider);
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
              : Text(
                  '音乐库',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
    return _trackFilter.filter(allTracks, _search.text);
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
      return GestureDetector(
        onSecondaryTapDown: (details) => _showTrackContextMenu(
          context,
          ref,
          tracks,
          track,
          details.globalPosition,
        ),
        child: ListTile(
          contentPadding: const EdgeInsetsDirectional.only(start: 16),
          minTileHeight: 64,
          leading: selectionMode
              ? Checkbox(
                  value: selectedTrackIds.contains(track.id),
                  onChanged: (_) => onToggleSelected(track),
                )
              : ArtworkView(bytes: track.artwork),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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
                position: PopupMenuPosition.under,
                offset: const Offset(-160, 4),
                tooltip: '更多操作',
                onSelected: (value) => _handleTrackMenuSelection(
                  context,
                  ref,
                  tracks,
                  track,
                  value,
                ),
                itemBuilder: (_) => _trackMenuItems(track),
              ),
            ],
          ),
          onTap: selectionMode
              ? () => onToggleSelected(track)
              : () => playOrOpenNowPlaying(
                  context,
                  ref,
                  tracks,
                  initialIndex: index,
                ),
          onLongPress: () => onLongPress(track),
        ),
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
      final names = byAlbum
          ? <String>[track.album]
          : splitArtistNames(track.artist);
      for (final name in names) {
        groups.putIfAbsent(name, () => []).add(track);
      }
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
            onTap: () => openCollectionPage(
              context,
              tracks,
              byAlbum ? CollectionKind.album : CollectionKind.artist,
              entry.key,
            ),
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
        Text(
          hasQuery ? '换个关键词试试' : '在 Android 扫描设备音乐，或在 Windows/Linux 添加音乐文件夹',
        ),
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

/// 歌曲操作菜单条目，供列表按钮与右键菜单复用，保证两处行为一致。
List<PopupMenuEntry<String>> _trackMenuItems(Track track) => [
  const PopupMenuItem(
    value: 'playlist',
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.playlist_add),
      title: Text('添加到歌单'),
    ),
  ),
  PopupMenuItem(
    value: 'artist',
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.person_outline),
      title: Text('查看歌手：${track.artist}'),
    ),
  ),
  PopupMenuItem(
    value: 'album',
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.album_outlined),
      title: Text('查看专辑：${track.album}'),
    ),
  ),
  if (_canOpenTrackDirectory(track))
    const PopupMenuItem(
      value: 'directory',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.folder_open_outlined),
        title: Text('打开所在目录'),
      ),
    ),
];

bool _canOpenTrackDirectory(Track track) =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) &&
    track.filePath != null;

Future<void> _handleTrackMenuSelection(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
  Track track,
  String value,
) async {
  switch (value) {
    case 'playlist':
      await _showPlaylistPicker(context, ref, track);
    case 'artist':
      await openArtistCollectionPage(context, tracks, track.artist);
    case 'album':
      openCollectionPage(context, tracks, CollectionKind.album, track.album);
    case 'directory':
      await openTrackDirectory(track.filePath);
  }
}

Future<void> _showTrackContextMenu(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
  Track track,
  Offset position,
) async {
  final value = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: _trackMenuItems(track),
  );
  if (!context.mounted || value == null) return;
  await _handleTrackMenuSelection(context, ref, tracks, track, value);
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
  await ref
      .read(databaseProvider)
      .addExistingTracksToPlaylist(
        selected.id,
        tracks.map((track) => track.id),
      );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已将 ${tracks.length} 首歌曲添加到“${selected.name}”')),
    );
  }
}
