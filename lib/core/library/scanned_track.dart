import 'dart:typed_data';

class ScannedTrack {
  const ScannedTrack({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.uri,
    required this.title,
    required this.artist,
    required this.album,
    this.filePath,
    this.durationMs,
    this.artwork,
    this.lyrics,
    this.fileSize,
    this.modifiedAt,
    this.contentFingerprint,
  });

  final String id;
  final String sourceType;
  final String sourceId;
  final String uri;
  final String? filePath;
  final String title;
  final String artist;
  final String album;
  final int? durationMs;
  final Uint8List? artwork;
  final String? lyrics;
  final int? fileSize;
  final DateTime? modifiedAt;
  final String? contentFingerprint;
}

class ScanResult {
  const ScanResult({
    required this.tracks,
    required this.sourceUri,
    required this.sourceLabel,
  });

  final List<ScannedTrack> tracks;
  final String sourceUri;
  final String sourceLabel;
}
