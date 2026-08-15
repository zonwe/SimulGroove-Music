import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'online_download_platform.dart';
import 'online_music_error.dart';
import 'online_track.dart';

OnlineDownloadPlatform createOnlineDownloadPlatform() =>
    IoOnlineDownloadPlatform();

class IoOnlineDownloadPlatform
    implements OnlineDownloadPlatform, OnlineDownloadCompanionPlatform {
  static const MethodChannel _androidChannel = MethodChannel(
    'top.zonwe.music_player/media_store',
  );

  @override
  bool get supported =>
      Platform.isAndroid || Platform.isWindows || Platform.isLinux;

  @override
  Future<OnlineDownloadDestination?> chooseDestination() async {
    if (Platform.isWindows || Platform.isLinux) {
      final selected = await getDirectoryPath(confirmButtonText: '选择下载文件夹');
      if (selected == null) return null;
      final path = p.normalize(selected);
      return OnlineDownloadDestination(uri: path, label: path);
    }
    if (Platform.isAndroid) {
      final selected = await _androidChannel.invokeMapMethod<String, Object?>(
        'pickDownloadDirectory',
      );
      if (selected == null) return null;
      final uri = selected['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;
      return OnlineDownloadDestination(
        uri: uri,
        label: selected['label'] as String? ?? '已授权下载目录',
      );
    }
    return null;
  }

  @override
  Future<DownloadedOnlineFile> save({
    required OnlineDownloadDestination destination,
    required OnlineTrack track,
    required OnlinePlaybackSource source,
    required String fileName,
  }) {
    if (Platform.isWindows || Platform.isLinux) {
      return _saveDesktop(destination, source, fileName);
    }
    if (Platform.isAndroid) {
      return _saveAndroid(destination, source, fileName);
    }
    throw UnsupportedError('当前平台暂不支持下载在线音乐。');
  }

  Future<DownloadedOnlineFile> _saveDesktop(
    OnlineDownloadDestination destination,
    OnlinePlaybackSource source,
    String fileName,
  ) async {
    final directory = Directory(destination.uri);
    if (!await directory.exists()) {
      throw const FileSystemException('下载目录不存在，请重新选择。');
    }
    final client = http.Client();
    File? partial;
    try {
      final request = http.Request('GET', source.url)
        ..headers.addAll(source.headers);
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OnlineMusicException(
          '下载请求失败（HTTP ${response.statusCode}）。',
          statusCode: response.statusCode,
          code: 'online_music_download_failed',
        );
      }
      final contentType = response.headers['content-type'];
      final resolvedName = _withAudioExtension(fileName, contentType);
      final output = await _uniqueDesktopFile(directory, resolvedName);
      partial = File('${output.path}.part');
      final sink = partial.openWrite();
      var bytes = 0;
      try {
        await for (final chunk in response.stream) {
          bytes += chunk.length;
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (bytes == 0) {
        throw const OnlineMusicException(
          '服务端返回了空的音频文件。',
          code: 'online_music_download_empty',
        );
      }
      await partial.rename(output.path);
      return DownloadedOnlineFile(
        uri: Uri.file(output.path).toString(),
        sourceType: Platform.isWindows ? 'windows_file' : 'linux_file',
        sourceId: output.path,
        filePath: output.path,
        bytes: bytes,
        fileName: p.basename(output.path),
        lyricsEmbedded: response.headers['x-online-lyrics-embedded'] == 'true',
        artworkEmbedded:
            response.headers['x-online-artwork-embedded'] == 'true',
      );
    } finally {
      client.close();
      if (partial != null && await partial.exists()) await partial.delete();
    }
  }

  Future<DownloadedOnlineFile> _saveAndroid(
    OnlineDownloadDestination destination,
    OnlinePlaybackSource source,
    String fileName,
  ) async {
    final result = await _androidChannel
        .invokeMapMethod<String, Object?>('downloadToTree', {
          'treeUri': destination.uri,
          'url': source.url.toString(),
          'headers': source.headers,
          'fileName': fileName,
          'mimeType': source.mimeType ?? 'application/octet-stream',
        });
    final uri = result?['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      throw const OnlineMusicException(
        'Android 未返回已下载文件的位置。',
        code: 'online_music_download_failed',
      );
    }
    return DownloadedOnlineFile(
      uri: uri,
      sourceType: 'android_document_tree',
      sourceId: '${destination.uri}/${result?['name'] ?? fileName}',
      bytes: (result?['bytes'] as num?)?.toInt() ?? 0,
      fileName: result?['name'] as String? ?? fileName,
      lyricsEmbedded: result?['lyricsEmbedded'] == true,
      artworkEmbedded: result?['artworkEmbedded'] == true,
    );
  }

  @override
  Future<void> saveCompanion({
    required OnlineDownloadDestination destination,
    required String fileName,
    required List<int> bytes,
    required String mimeType,
  }) async {
    if (bytes.isEmpty) return;
    if (Platform.isWindows || Platform.isLinux) {
      final directory = Directory(destination.uri);
      if (!await directory.exists()) {
        throw const FileSystemException('下载目录不存在，请重新选择。');
      }
      final output = await _uniqueDesktopFile(directory, fileName);
      await output.writeAsBytes(bytes, flush: true);
      return;
    }
    if (Platform.isAndroid) {
      await _androidChannel.invokeMethod<void>('saveBytesToTree', {
        'treeUri': destination.uri,
        'fileName': fileName,
        'mimeType': mimeType,
        'bytes': Uint8List.fromList(bytes),
      });
      return;
    }
    throw UnsupportedError('当前平台暂不支持保存下载附件。');
  }

  String _withAudioExtension(String fileName, String? mimeType) {
    final extension = switch (mimeType?.split(';').first.toLowerCase()) {
      'audio/flac' => '.flac',
      'audio/mp4' || 'audio/x-m4a' => '.m4a',
      'audio/aac' => '.aac',
      'audio/wav' || 'audio/x-wav' => '.wav',
      'audio/ogg' => '.ogg',
      'audio/opus' => '.opus',
      _ => '.mp3',
    };
    return '${p.basenameWithoutExtension(fileName)}$extension';
  }

  Future<File> _uniqueDesktopFile(Directory directory, String name) async {
    final extension = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    var candidate = File(p.join(directory.path, name));
    var suffix = 2;
    while (await candidate.exists() ||
        await File('${candidate.path}.part').exists()) {
      candidate = File(p.join(directory.path, '$stem ($suffix)$extension'));
      suffix++;
    }
    return candidate;
  }
}
