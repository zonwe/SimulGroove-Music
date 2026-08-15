import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'online_download_platform.dart';
import 'online_track.dart';

String onlineTrackLibraryId(OnlineTrack track) => 'online:${track.id}';

TracksCompanion onlineTrackPlaceholder(OnlineTrack track) {
  final now = DateTime.now();
  return TracksCompanion.insert(
    id: onlineTrackLibraryId(track),
    sourceType: 'online',
    sourceId: track.id,
    uri: _persistentUri(track).toString(),
    title: track.title,
    artist: Value(track.artists.isEmpty ? '未知艺术家' : track.artists.join('、')),
    album: Value(track.album.isEmpty ? '未知专辑' : track.album),
    durationMs: Value(track.durationMs),
    updatedAt: now,
  );
}

TracksCompanion downloadedOnlineTrack(
  OnlineTrack track,
  DownloadedOnlineFile file, {
  Uint8List? artwork,
  String? lyrics,
}) => TracksCompanion.insert(
  id: onlineTrackLibraryId(track),
  sourceType: file.sourceType,
  sourceId: file.sourceId,
  uri: file.uri,
  filePath: Value(file.filePath),
  title: track.title,
  artist: Value(track.artists.isEmpty ? '未知艺术家' : track.artists.join('、')),
  album: Value(track.album.isEmpty ? '未知专辑' : track.album),
  durationMs: Value(track.durationMs),
  artwork: Value(artwork),
  lyrics: Value(lyrics),
  fileSize: Value(file.bytes > 0 ? file.bytes : null),
  modifiedAt: Value(DateTime.now()),
  updatedAt: DateTime.now(),
);

OnlineTrack? onlineTrackFromDatabase(Track track) {
  if (track.sourceType != 'online') return null;
  final uri = Uri.tryParse(track.uri);
  if (uri == null ||
      uri.scheme != 'online-music' ||
      uri.host != 'track' ||
      uri.pathSegments.length != 2) {
    return null;
  }
  final capabilities = (uri.queryParameters['capabilities'] ?? '')
      .split(',')
      .where((value) => value.isNotEmpty)
      .toSet();
  return OnlineTrack(
    provider: uri.pathSegments[0],
    trackId: uri.pathSegments[1],
    title: track.title,
    artists: track.artist.isEmpty ? const [] : [track.artist],
    album: track.album,
    durationMs: track.durationMs,
    artworkUrl: uri.queryParameters['artworkUrl'],
    playable: capabilities.contains('playback'),
    capabilities: capabilities,
  );
}

Uri _persistentUri(OnlineTrack track) {
  final queryParameters = <String, String>{
    'capabilities': (track.capabilities.toList()..sort()).join(','),
  };
  final artworkUrl = track.artworkUrl;
  if (artworkUrl != null) queryParameters['artworkUrl'] = artworkUrl;
  return Uri(
    scheme: 'online-music',
    host: 'track',
    pathSegments: [track.provider, track.trackId],
    queryParameters: queryParameters,
  );
}
