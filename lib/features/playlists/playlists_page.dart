import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../library/artwork_view.dart';

class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key, required this.onOpenPlaylist});

  final ValueChanged<Playlist> onOpenPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '歌单',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _createPlaylist(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('新建歌单'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: playlists.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('歌单读取失败：$error')),
              data: (values) => values.isEmpty
                  ? const Center(child: Text('还没有歌单，新建一个并从音乐库添加歌曲吧。'))
                  : ListView.separated(
                      itemCount: values.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _PlaylistCard(
                        playlist: values[index],
                        onOpen: () => onOpenPlaylist(values[index]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '歌单名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final now = DateTime.now();
    await ref
        .read(databaseProvider)
        .createPlaylist(
          PlaylistsCompanion.insert(
            id: const Uuid().v4(),
            name: name,
            accountId: Value(ref.read(accountProvider).value?.id),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}

class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({required this.playlist, required this.onOpen});

  final Playlist playlist;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<Track>>(
      stream: ref.read(databaseProvider).watchPlaylistTracks(playlist.id),
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? const <Track>[];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            minTileHeight: 72,
            contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            leading: ArtworkView(
              bytes: tracks.firstOrNull?.artwork,
              size: 52,
              borderRadius: 8,
            ),
            title: Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(tracks.isEmpty ? '暂无歌曲' : '${tracks.length} 首歌曲'),
            trailing: PopupMenuButton<String>(
              tooltip: '歌单操作',
              onSelected: (value) {
                if (value == 'delete') {
                  _deletePlaylist(context, ref, playlist);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline),
                    title: Text('删除歌单'),
                  ),
                ),
              ],
            ),
            onTap: onOpen,
          ),
        );
      },
    );
  }
}

Future<void> _deletePlaylist(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除歌单'),
      content: Text('确定删除“${playlist.name}”吗？歌曲文件不会被删除。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(databaseProvider).deletePlaylist(playlist.id);
  }
}
