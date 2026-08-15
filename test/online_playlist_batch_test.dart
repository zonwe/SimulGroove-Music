import 'package:drift/native.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/core/online_music/online_track.dart';
import 'package:flutter_music/core/online_music/online_track_persistence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('在线搜索结果可按选择顺序原子写入新歌单', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    const tracks = [
      OnlineTrack(
        provider: 'source/a',
        trackId: 'track/1',
        title: '第一首',
        artists: ['歌手甲'],
        album: '专辑',
        playable: true,
        capabilities: {'playback', 'artwork'},
        artworkUrl: '/api/online-music/tracks/source/track/cover',
      ),
      OnlineTrack(
        provider: 'source-b',
        trackId: 'track-2',
        title: '第二首',
        artists: ['歌手乙'],
        album: '专辑',
        playable: true,
        capabilities: {'playback'},
      ),
    ];

    await database.createPlaylistWithTracks(
      PlaylistsCompanion.insert(
        id: 'online-playlist',
        name: '在线收藏',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      tracks.map(onlineTrackPlaceholder),
    );

    final stored = await database.watchPlaylistTracks('online-playlist').first;
    expect(stored.map((track) => track.title), ['第一首', '第二首']);
    expect(stored.every((track) => track.sourceType == 'online'), isTrue);
    final restored = onlineTrackFromDatabase(stored.first);
    expect(restored?.provider, 'source/a');
    expect(restored?.trackId, 'track/1');
    expect(restored?.capabilities, {'artwork', 'playback'});
  });
}
