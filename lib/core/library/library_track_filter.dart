import '../database/app_database.dart';

/// Cache searchable text until the database emits a different track list.
class LibraryTrackFilter {
  List<Track>? _source;
  List<String> _searchText = const [];
  String? _query;
  List<Track> _result = const [];

  List<Track> filter(List<Track> tracks, String query) {
    final normalized = query.trim().toLowerCase();
    if (!identical(tracks, _source)) {
      _source = tracks;
      _searchText = [
        for (final track in tracks)
          '${track.title}\n${track.artist}\n${track.album}'.toLowerCase(),
      ];
      _query = null;
    }
    if (_query != normalized) {
      _query = normalized;
      _result = normalized.isEmpty
          ? tracks
          : List.unmodifiable([
              for (var i = 0; i < tracks.length; i++)
                if (_searchText[i].contains(normalized)) tracks[i],
            ]);
    }
    return _result;
  }
}
