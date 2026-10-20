import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../log/app_log.dart';
import 'online_download_platform.dart';
import 'online_music_repository.dart';
import 'online_track.dart';
import 'online_track_persistence.dart';

const onlineDownloadDirectorySettingKey = 'online_download_directory';
const onlineDownloadDirectoryLabelSettingKey =
    'online_download_directory_label';
const onlineDownloadFilenameFormatSettingKey =
    'online_download_filename_format';

enum OnlineDownloadFilenameFormat { artistTitle, titleArtist, titleOnly }

OnlineDownloadFilenameFormat parseOnlineDownloadFilenameFormat(String? value) =>
    switch (value) {
      'title_artist' => OnlineDownloadFilenameFormat.titleArtist,
      'title_only' => OnlineDownloadFilenameFormat.titleOnly,
      _ => OnlineDownloadFilenameFormat.artistTitle,
    };

String serializeOnlineDownloadFilenameFormat(
  OnlineDownloadFilenameFormat format,
) => switch (format) {
  OnlineDownloadFilenameFormat.artistTitle => 'artist_title',
  OnlineDownloadFilenameFormat.titleArtist => 'title_artist',
  OnlineDownloadFilenameFormat.titleOnly => 'title_only',
};

typedef ReadDownloadSetting = Future<String?> Function(String key);
typedef WriteDownloadSetting = Future<void> Function(String key, String value);
typedef SaveDownloadedTrack = Future<void> Function(TracksCompanion track);

class OnlineDownloadProgress {
  const OnlineDownloadProgress({
    required this.completed,
    required this.total,
    this.currentTrackId,
  });

  final int completed;
  final int total;
  final String? currentTrackId;
}

class OnlineDownloadFailure {
  const OnlineDownloadFailure(this.track, this.error);

  final OnlineTrack track;
  final Object error;
}

class OnlineDownloadBatchResult {
  const OnlineDownloadBatchResult({
    required this.downloaded,
    required this.failures,
    this.warnings = const [],
  });

  final List<OnlineTrack> downloaded;
  final List<OnlineDownloadFailure> failures;
  final List<OnlineDownloadWarning> warnings;
}

enum OnlineDownloadAsset { artwork, lyrics }

class OnlineDownloadWarning {
  const OnlineDownloadWarning(
    this.track,
    this.file,
    this.destination,
    this.assets,
  );

  final OnlineTrack track;
  final DownloadedOnlineFile file;
  final OnlineDownloadDestination destination;
  final Set<OnlineDownloadAsset> assets;
}

abstract interface class OnlineDownloadAttachmentRetrier {
  Future<List<OnlineDownloadWarning>> retryAttachments(
    List<OnlineDownloadWarning> warnings,
  );
}

abstract interface class OnlineTrackDownloader {
  bool get supported;

  Future<OnlineDownloadDestination?> destination();

  Future<OnlineDownloadDestination?> chooseDestination();

  Future<OnlineDownloadBatchResult> downloadAll(
    List<OnlineTrack> tracks, {
    void Function(OnlineDownloadProgress progress)? onProgress,
  });
}

class DefaultOnlineTrackDownloader
    implements OnlineTrackDownloader, OnlineDownloadAttachmentRetrier {
  factory DefaultOnlineTrackDownloader({
    required OnlineMusicSearchRepository repository,
    required OnlineDownloadPlatform platform,
    required ReadDownloadSetting readSetting,
    required WriteDownloadSetting writeSetting,
    required SaveDownloadedTrack saveDownloadedTrack,
  }) => DefaultOnlineTrackDownloader._(
    repository,
    platform,
    readSetting,
    writeSetting,
    saveDownloadedTrack,
  );

  DefaultOnlineTrackDownloader._(
    this._repository,
    this._platform,
    this._readSetting,
    this._writeSetting,
    this._saveDownloadedTrack,
  );

  final OnlineMusicSearchRepository _repository;
  final OnlineDownloadPlatform _platform;
  final ReadDownloadSetting _readSetting;
  final WriteDownloadSetting _writeSetting;
  final SaveDownloadedTrack _saveDownloadedTrack;
  OnlineDownloadDestination? _destination;

  @override
  bool get supported => _platform.supported;

  @override
  Future<OnlineDownloadDestination?> destination() async {
    if (_destination case final destination?) return destination;
    final uri = await _readSetting(onlineDownloadDirectorySettingKey);
    if (uri == null || uri.isEmpty) return null;
    final label = await _readSetting(onlineDownloadDirectoryLabelSettingKey);
    return _destination = OnlineDownloadDestination(
      uri: uri,
      label: label?.isNotEmpty == true ? label! : uri,
    );
  }

  @override
  Future<OnlineDownloadDestination?> chooseDestination() async {
    final selected = await _platform.chooseDestination();
    if (selected == null) return null;
    await _writeSetting(onlineDownloadDirectorySettingKey, selected.uri);
    await _writeSetting(onlineDownloadDirectoryLabelSettingKey, selected.label);
    _destination = selected;
    return selected;
  }

  @override
  Future<OnlineDownloadBatchResult> downloadAll(
    List<OnlineTrack> tracks, {
    void Function(OnlineDownloadProgress progress)? onProgress,
  }) async {
    final target = await destination();
    if (target == null) {
      throw StateError('请先选择下载目录。');
    }
    final downloaded = <OnlineTrack>[];
    final failures = <OnlineDownloadFailure>[];
    final warnings = <OnlineDownloadWarning>[];
    var completed = 0;
    final filenameFormat = parseOnlineDownloadFilenameFormat(
      await _readSetting(onlineDownloadFilenameFormatSettingKey),
    );
    for (final track in tracks) {
      onProgress?.call(
        OnlineDownloadProgress(
          completed: completed,
          total: tracks.length,
          currentTrackId: track.id,
        ),
      );
      try {
        final repository = _repository;
        final source = repository is OnlineMusicDownloadRepository
            ? await (repository as OnlineMusicDownloadRepository)
                  .prepareDownload(track)
            : await repository.preparePlayback(track);
        final file = await _platform.save(
          destination: target,
          track: track,
          source: source,
          fileName: _fileName(track, source.mimeType, filenameFormat),
        );
        // Commit the playable audio before attempting optional resources.
        await _saveDownloadedTrack(downloadedOnlineTrack(track, file));
        downloaded.add(track);
        final warning = await _saveAttachments(target, track, file, {
          if (!file.artworkEmbedded && track.capabilities.contains('artwork'))
            OnlineDownloadAsset.artwork,
          if (!file.lyricsEmbedded && track.capabilities.contains('lyrics'))
            OnlineDownloadAsset.lyrics,
        }, fallbackName: _fileName(track, source.mimeType, filenameFormat));
        if (warning != null) warnings.add(warning);
      } catch (error) {
        failures.add(OnlineDownloadFailure(track, error));
      }
      completed++;
      onProgress?.call(
        OnlineDownloadProgress(completed: completed, total: tracks.length),
      );
    }
    return OnlineDownloadBatchResult(
      downloaded: List.unmodifiable(downloaded),
      failures: List.unmodifiable(failures),
      warnings: List.unmodifiable(warnings),
    );
  }

  @override
  Future<List<OnlineDownloadWarning>> retryAttachments(
    List<OnlineDownloadWarning> warnings,
  ) async {
    final remaining = <OnlineDownloadWarning>[];
    for (final warning in warnings) {
      final result = await _saveAttachments(
        warning.destination,
        warning.track,
        warning.file,
        warning.assets,
      );
      if (result != null) remaining.add(result);
    }
    return List.unmodifiable(remaining);
  }

  Future<OnlineDownloadWarning?> _saveAttachments(
    OnlineDownloadDestination target,
    OnlineTrack track,
    DownloadedOnlineFile file,
    Set<OnlineDownloadAsset> assets, {
    String? fallbackName,
  }) async {
    if (assets.isEmpty) return null;
    final failed = <OnlineDownloadAsset>{};
    final platform = _platform;
    final companion = platform is OnlineDownloadCompanionPlatform
        ? platform as OnlineDownloadCompanionPlatform
        : null;
    final stem = p.basenameWithoutExtension(
      file.fileName ??
          fallbackName ??
          file.filePath ??
          Uri.parse(file.uri).pathSegments.lastOrNull ??
          '歌曲',
    );
    for (final asset in assets) {
      try {
        switch (asset) {
          case OnlineDownloadAsset.artwork:
            final bytes = await _repository.loadArtwork(track);
            if (bytes == null) continue;
            await _saveDownloadedTrack(
              downloadedOnlineTrack(
                track,
                file,
                artwork: bytes,
              ).copyWith(lyrics: const Value.absent()),
            );
            if (companion != null) {
              final type = _artworkType(bytes);
              await companion.saveCompanion(
                destination: target,
                fileName: '$stem.${type.$2}',
                bytes: bytes,
                mimeType: type.$1,
              );
            }
          case OnlineDownloadAsset.lyrics:
            final lyrics = await _repository.loadLyrics(track);
            if (lyrics == null) continue;
            await _saveDownloadedTrack(
              downloadedOnlineTrack(
                track,
                file,
                lyrics: lyrics,
              ).copyWith(artwork: const Value.absent()),
            );
            if (companion != null) {
              await companion.saveCompanion(
                destination: target,
                fileName: '$stem.lrc',
                bytes: Uint8List.fromList(utf8.encode(lyrics)),
                mimeType: 'text/plain',
              );
            }
        }
      } catch (error, stackTrace) {
        failed.add(asset);
        AppLog.warning('下载音频的附加资源保存失败：${asset.name}', error, stackTrace);
      }
    }
    return failed.isEmpty
        ? null
        : OnlineDownloadWarning(track, file, target, Set.unmodifiable(failed));
  }

  String _fileName(
    OnlineTrack track,
    String? mimeType,
    OnlineDownloadFilenameFormat format,
  ) {
    final artist = track.artists.isEmpty ? '未知艺术家' : track.artists.first;
    final baseName = switch (format) {
      OnlineDownloadFilenameFormat.artistTitle => '$artist - ${track.title}',
      OnlineDownloadFilenameFormat.titleArtist => '${track.title} - $artist',
      OnlineDownloadFilenameFormat.titleOnly => track.title,
    };
    final raw = baseName
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    final stem = raw.isEmpty ? '在线音乐' : raw;
    return '$stem${_extensionFor(mimeType)}';
  }

  String _extensionFor(String? mimeType) =>
      switch (mimeType?.split(';').first.trim().toLowerCase()) {
        'audio/flac' => '.flac',
        'audio/mp4' || 'audio/x-m4a' => '.m4a',
        'audio/aac' => '.aac',
        'audio/wav' || 'audio/x-wav' => '.wav',
        'audio/ogg' => '.ogg',
        'audio/opus' => '.opus',
        _ => '.mp3',
      };

  (String, String) _artworkType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return ('image/png', 'png');
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return ('image/webp', 'webp');
    }
    return ('image/jpeg', 'jpg');
  }
}
