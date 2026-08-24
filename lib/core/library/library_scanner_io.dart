import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import 'library_scanner.dart';
import 'scanned_track.dart';

LibraryScanner createLibraryScanner() => IoLibraryScanner();

class IoLibraryScanner implements LibraryScanner {
  final Uuid _uuid = const Uuid();
  static const MethodChannel _mediaStore = MethodChannel(
    'top.zonwe.simul_groove_player/media_store',
  );

  @override
  bool get isSupported =>
      Platform.isAndroid || Platform.isWindows || Platform.isLinux;

  @override
  bool get supportsFullDeviceScan => Platform.isAndroid;

  @override
  String get actionLabel => '添加音乐文件夹';

  @override
  Future<ScanResult?> scan() {
    if (Platform.isAndroid) return _scanAndroidDirectory();
    if (Platform.isWindows || Platform.isLinux) return _scanDesktop();
    return Future.value();
  }

  @override
  Future<ScanResult?> scanFullDevice() {
    if (Platform.isAndroid) return _scanAndroidFullDevice();
    return Future.value();
  }

  @override
  Future<ScanResult?> rescanSource({
    required String sourceUri,
    required String platform,
    required String sourceLabel,
  }) {
    if (sourceUri == 'media-store://external') {
      return _scanAndroidFullDevice();
    }
    if (Platform.isAndroid && sourceUri.startsWith('content://')) {
      return _scanAndroidDirectoryUri(sourceUri, sourceLabel);
    }
    if (Platform.isWindows || Platform.isLinux) {
      return Isolate.run(
        () => scanDesktopDirectory(sourceUri, isWindows: Platform.isWindows),
      );
    }
    return Future.value();
  }

  Future<ScanResult?> _scanAndroidDirectory() async {
    final selected = await _mediaStore.invokeMapMethod<String, Object?>(
      'pickAudioDirectory',
    );
    if (selected == null) return null;
    final uri = selected['uri']! as String;
    final label = selected['label'] as String? ?? '已授权音乐目录';
    return _scanAndroidDirectoryUri(uri, label);
  }

  Future<ScanResult?> _scanAndroidDirectoryUri(String uri, String label) async {
    final rawSongs =
        await _mediaStore.invokeListMethod<Object?>('scanAudioTree', {
          'uri': uri,
        }) ??
        const [];
    return ScanResult(
      tracks: await _mapAndroidTracks(
        rawSongs,
        sourceType: 'android_document_tree',
        sourceUri: uri,
      ),
      sourceUri: uri,
      sourceLabel: label,
    );
  }

  Future<ScanResult?> _scanAndroidFullDevice() async {
    var permission = await Permission.audio.request();
    if (!permission.isGranted) {
      permission = await Permission.storage.request();
    }
    if (!permission.isGranted) {
      throw const FileSystemException('未获得读取本地音乐的权限');
    }
    final rawSongs =
        await _mediaStore.invokeListMethod<Object?>('scanAudio') ?? const [];
    return ScanResult(
      tracks: await _mapAndroidTracks(
        rawSongs,
        sourceType: 'android_media_store',
      ),
      sourceUri: 'media-store://external',
      sourceLabel: '整台设备',
    );
  }

  Future<List<ScannedTrack>> _mapAndroidTracks(
    List<Object?> rawSongs, {
    required String sourceType,
    String? sourceUri,
  }) async {
    // MediaStore exposes a filesystem path for many device-wide scans. Parse
    // those files off the UI isolate so embedded lyrics are preferred without
    // making a large library scan jank the app. Document Tree providers may
    // not expose a path; their native sidecar lookup remains the fallback.
    final audioPaths = <String>{};
    for (final raw in rawSongs) {
      final path = Map<Object?, Object?>.from(raw! as Map)['path'] as String?;
      if (path != null && path.isNotEmpty) audioPaths.add(path);
    }
    final audioPathList = audioPaths.toList(growable: false);
    final embeddedLyricsByPath = audioPathList.isEmpty
        ? const <String, String?>{}
        : await Isolate.run(() => _readEmbeddedLyricsByPath(audioPathList));
    final tracks = <ScannedTrack>[];
    for (final raw in rawSongs) {
      final song = Map<Object?, Object?>.from(raw! as Map);
      final mediaUri = song['uri']! as String;
      final data = song['path'] as String?;
      final embeddedLyrics = data == null
          ? null
          : _cleanLyrics(embeddedLyricsByPath[data]);
      tracks.add(
        ScannedTrack(
          id: _uuid.v5(Namespace.url.value, mediaUri),
          sourceType: sourceType,
          sourceId: sourceUri == null
              ? song['id'].toString()
              : '$sourceUri/${song['id']}',
          uri: mediaUri,
          filePath: data,
          title: _clean(
            song['title'] as String?,
            song['displayName'] as String? ?? '未知歌曲',
          ),
          artist: _clean(song['artist'] as String?, '未知艺术家'),
          album: _clean(song['album'] as String?, '未知专辑'),
          durationMs: song['duration'] as int?,
          artwork: _compactArtwork(song['artwork'] as Uint8List?),
          lyrics:
              embeddedLyrics ??
              _cleanLyrics(song['lyrics'] as String?) ??
              (data == null ? null : await _tryReadSidecarLyrics(data)),
          fileSize: song['size'] as int?,
          modifiedAt: song['dateModifiedMs'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  song['dateModifiedMs'] as int,
                )
              : song['dateModified'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (song['dateModified'] as int) * 1000,
                ),
        ),
      );
    }
    return tracks;
  }

  Future<ScanResult?> _scanDesktop() async {
    final selected = await getDirectoryPath(confirmButtonText: '选择音乐文件夹');
    if (selected == null) return null;
    // Directory walking and synchronous metadata parsing happen off the UI
    // isolate. The picker itself must stay on the platform/UI isolate.
    return Isolate.run(
      () => scanDesktopDirectory(selected, isWindows: Platform.isWindows),
    );
  }

  Future<String?> _tryReadSidecarLyrics(String audioPath) async {
    try {
      final lrc = File(p.setExtension(audioPath, '.lrc'));
      if (await lrc.exists()) return _cleanLyrics(await lrc.readAsString());
    } catch (_) {
      // Scoped storage may allow audio but not a sidecar text file.
    }
    return null;
  }

  String _clean(String? value, String fallback) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == '<unknown>') {
      return fallback;
    }
    return trimmed;
  }

  String? _cleanLyrics(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Uint8List? _compactArtwork(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final decoded = image.decodeImage(bytes);
      if (decoded == null) return bytes.length <= 512 * 1024 ? bytes : null;
      final longestSide = decoded.width > decoded.height
          ? decoded.width
          : decoded.height;
      final thumbnail = longestSide > 320
          ? image.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? 320 : null,
              height: decoded.height > decoded.width ? 320 : null,
              interpolation: image.Interpolation.average,
            )
          : decoded;
      return Uint8List.fromList(image.encodeJpg(thumbnail, quality: 70));
    } catch (_) {
      return bytes.length <= 512 * 1024 ? bytes : null;
    }
  }
}

Map<String, String?> _readEmbeddedLyricsByPath(List<String> paths) {
  final lyricsByPath = <String, String?>{};
  for (final path in paths) {
    try {
      final lyrics = readMetadata(File(path), getImage: false).lyrics?.trim();
      lyricsByPath[path] = lyrics == null || lyrics.isEmpty ? null : lyrics;
    } catch (_) {
      // A malformed tag must not exclude an otherwise playable track.
      lyricsByPath[path] = null;
    }
  }
  return lyricsByPath;
}

@visibleForTesting
Future<ScanResult> scanDesktopDirectory(
  String selected, {
  required bool isWindows,
}) async {
  final uuid = const Uuid();
  final directory = Directory(selected);
  if (!await directory.exists()) throw const FileSystemException('所选文件夹不存在');

  final files = await directory
      .list(recursive: true, followLinks: false)
      .where((entry) => entry is File && _isDesktopAudioFile(entry.path))
      .cast<File>()
      .toList();
  final tracks = <ScannedTrack>[];
  for (final file in files) {
    final stat = await file.stat();
    AudioMetadata? metadata;
    try {
      metadata = readMetadata(file, getImage: true);
    } catch (_) {
      // A playable file may have malformed or missing tags; keep it in the library.
    }
    final canonicalPath = p.normalize(file.absolute.path);
    final stablePath = isWindows ? canonicalPath.toLowerCase() : canonicalPath;
    final sourceType = isWindows ? 'windows_file' : 'linux_file';
    tracks.add(
      ScannedTrack(
        id: uuid.v5(Namespace.url.value, stablePath),
        sourceType: sourceType,
        sourceId: canonicalPath,
        uri: Uri.file(canonicalPath).toString(),
        filePath: canonicalPath,
        title: _cleanDesktopValue(
          metadata?.title,
          p.basenameWithoutExtension(canonicalPath),
        ),
        artist: _cleanDesktopValue(metadata?.artist, '未知艺术家'),
        album: _cleanDesktopValue(metadata?.album, '未知专辑'),
        durationMs: metadata?.duration?.inMilliseconds,
        artwork: _compactDesktopArtwork(
          metadata?.pictures.isEmpty ?? true
              ? null
              : metadata!.pictures.first.bytes,
        ),
        lyrics:
            _cleanDesktopLyrics(metadata?.lyrics) ??
            await _readDesktopSidecarLyrics(canonicalPath),
        fileSize: stat.size,
        modifiedAt: stat.modified,
      ),
    );
  }
  return ScanResult(
    tracks: tracks,
    sourceUri: p.normalize(directory.absolute.path),
    sourceLabel: p.basename(p.normalize(selected)).isEmpty
        ? p.normalize(selected)
        : p.basename(p.normalize(selected)),
  );
}

bool _isDesktopAudioFile(String path) {
  const extensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
    '.opus',
    '.wma',
  };
  return extensions.contains(p.extension(path).toLowerCase());
}

Future<String?> _readDesktopSidecarLyrics(String audioPath) async {
  try {
    final lrc = File(p.setExtension(audioPath, '.lrc'));
    if (await lrc.exists()) {
      return _cleanDesktopLyrics(await lrc.readAsString());
    }
  } catch (_) {
    // A sidecar file may be inaccessible even when the audio file is readable.
  }
  return null;
}

String _cleanDesktopValue(String? value, String fallback) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed == '<unknown>') {
    return fallback;
  }
  return trimmed;
}

String? _cleanDesktopLyrics(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Uint8List? _compactDesktopArtwork(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final decoded = image.decodeImage(bytes);
    if (decoded == null) return bytes.length <= 512 * 1024 ? bytes : null;
    final longestSide = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    final thumbnail = longestSide > 320
        ? image.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 320 : null,
            height: decoded.height > decoded.width ? 320 : null,
            interpolation: image.Interpolation.average,
          )
        : decoded;
    return Uint8List.fromList(image.encodeJpg(thumbnail, quality: 70));
  } catch (_) {
    return bytes.length <= 512 * 1024 ? bytes : null;
  }
}
