import 'online_track.dart';

class OnlineDownloadDestination {
  const OnlineDownloadDestination({required this.uri, required this.label});

  final String uri;
  final String label;
}

class DownloadedOnlineFile {
  const DownloadedOnlineFile({
    required this.uri,
    required this.sourceType,
    required this.sourceId,
    required this.bytes,
    this.filePath,
    this.fileName,
    this.lyricsEmbedded = false,
    this.artworkEmbedded = false,
  });

  final String uri;
  final String sourceType;
  final String sourceId;
  final String? filePath;
  final int bytes;
  final String? fileName;
  final bool lyricsEmbedded;
  final bool artworkEmbedded;
}

abstract interface class OnlineDownloadCompanionPlatform {
  Future<void> saveCompanion({
    required OnlineDownloadDestination destination,
    required String fileName,
    required List<int> bytes,
    required String mimeType,
  });
}

abstract interface class OnlineDownloadPlatform {
  bool get supported;

  Future<OnlineDownloadDestination?> chooseDestination();

  Future<DownloadedOnlineFile> save({
    required OnlineDownloadDestination destination,
    required OnlineTrack track,
    required OnlinePlaybackSource source,
    required String fileName,
  });
}
