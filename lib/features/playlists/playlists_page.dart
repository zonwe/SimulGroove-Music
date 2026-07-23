import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../library/artwork_view.dart';

class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

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
                      itemBuilder: (context, index) =>
                          _PlaylistCard(playlist: values[index]),
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
  const _PlaylistCard({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: ExpansionTile(
      leading: const SizedBox.square(
        dimension: 48,
        child: Icon(Icons.queue_music, size: 30),
      ),
      title: Text(playlist.name),
      subtitle: const Text('展开查看歌曲'),
      trailing: IconButton(
        tooltip: '删除歌单',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => ref.read(databaseProvider).deletePlaylist(playlist.id),
      ),
      children: [
        StreamBuilder<List<Track>>(
          stream: ref.read(databaseProvider).watchPlaylistTracks(playlist.id),
          builder: (context, snapshot) {
            final tracks = snapshot.data ?? const <Track>[];
            if (tracks.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Text('歌单中还没有歌曲'),
              );
            }
            return Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          ref.read(audioHandlerProvider).playTracks(tracks),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('播放全部'),
                    ),
                  ),
                ),
                for (var index = 0; index < tracks.length; index++)
                  ListTile(
                    leading: ArtworkView(
                      bytes: tracks[index].artwork,
                      size: 42,
                    ),
                    title: Text(tracks[index].title),
                    subtitle: Text(tracks[index].artist),
                    onTap: () => ref
                        .read(audioHandlerProvider)
                        .playTracks(tracks, initialIndex: index),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
