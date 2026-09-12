import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/core/library/library_track_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'search matches title, artist and album and refreshes after library changes',
    () {
      final filter = LibraryTrackFilter();
      final tracks = [
        _track('a', 'Hello', '歌手', 'Album'),
        _track('b', 'Other', '', ''),
      ];
      expect(filter.filter(tracks, ' hello ').single.id, 'a');
      expect(filter.filter(tracks, '歌手').single.id, 'a');
      expect(filter.filter(tracks, 'ALBUM').single.id, 'a');
      expect(filter.filter(tracks, '').length, 2);
      expect(filter.filter(tracks, 'missing'), isEmpty);
      expect(
        filter.filter([_track('c', 'missing', '', '')], 'missing').single.id,
        'c',
      );
    },
  );
}

Track _track(String id, String title, String artist, String album) => Track(
  id: id,
  sourceType: 'test',
  sourceId: id,
  uri: 'test://$id',
  title: title,
  artist: artist,
  album: album,
  isAvailable: true,
  syncState: 'local',
  updatedAt: DateTime(2026),
);
