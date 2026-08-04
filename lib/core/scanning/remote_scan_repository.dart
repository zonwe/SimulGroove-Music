import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_repository.dart';
import '../auth/backend_gateway.dart';

class RemoteScanSource {
  const RemoteScanSource({
    required this.id,
    required this.path,
    required this.intervalMinutes,
    required this.enabled,
    required this.status,
    required this.trackCount,
    this.lastScanAt,
    this.nextScanAt,
    this.lastError,
  });

  final String id;
  final String path;
  final int intervalMinutes;
  final bool enabled;
  final String status;
  final int trackCount;
  final DateTime? lastScanAt;
  final DateTime? nextScanAt;
  final String? lastError;

  bool get isScanning => status == 'scanning';
  bool get hasFailed => status == 'failed';

  factory RemoteScanSource.fromJson(Map<String, dynamic> json) =>
      RemoteScanSource(
        id: json['id'] as String,
        path: json['path'] as String,
        intervalMinutes: json['intervalMinutes'] as int,
        enabled: json['enabled'] as bool,
        status: json['status'] as String,
        trackCount: json['trackCount'] as int,
        lastScanAt: _date(json['lastScanAt']),
        nextScanAt: _date(json['nextScanAt']),
        lastError: json['lastError'] as String?,
      );

  static DateTime? _date(Object? value) => value is String && value.isNotEmpty
      ? DateTime.parse(value).toLocal()
      : null;
}

class RemoteScannedTrack {
  const RemoteScannedTrack({
    required this.id,
    required this.filePath,
    required this.title,
    required this.artist,
    required this.album,
    required this.extension,
    required this.fileSize,
    required this.modifiedAt,
  });

  final String id;
  final String filePath;
  final String title;
  final String artist;
  final String album;
  final String extension;
  final int fileSize;
  final DateTime modifiedAt;

  factory RemoteScannedTrack.fromJson(Map<String, dynamic> json) =>
      RemoteScannedTrack(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String,
        extension: json['extension'] as String,
        fileSize: json['fileSize'] as int,
        modifiedAt: DateTime.parse(json['modifiedAt'] as String).toLocal(),
      );
}

class RemoteScanRepository {
  RemoteScanRepository(
    this._authRepository, {
    String? baseUrl,
    http.Client? client,
  }) : _baseUrl = (baseUrl ?? defaultBackendBaseUrl).replaceFirst(
         RegExp(r'/$'),
         '',
       ),
       _client = client ?? http.Client();

  final AuthRepository _authRepository;
  final String _baseUrl;
  final http.Client _client;

  Future<List<RemoteScanSource>> listSources() async {
    final response = await _request('GET', '/api/scan-sources/');
    return (jsonDecode(response.body) as List<dynamic>)
        .map(
          (value) =>
              RemoteScanSource.fromJson((value as Map).cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  Future<RemoteScanSource> createSource({
    required String path,
    required int intervalMinutes,
    bool enabled = true,
  }) async {
    final response = await _request(
      'POST',
      '/api/scan-sources/',
      body: {
        'path': path,
        'intervalMinutes': intervalMinutes,
        'enabled': enabled,
      },
    );
    return RemoteScanSource.fromJson(_jsonObject(response));
  }

  Future<RemoteScanSource> updateSource(
    RemoteScanSource source, {
    String? path,
    int? intervalMinutes,
    bool? enabled,
  }) async {
    final response = await _request(
      'PUT',
      '/api/scan-sources/${source.id}',
      body: {
        'path': path ?? source.path,
        'intervalMinutes': intervalMinutes ?? source.intervalMinutes,
        'enabled': enabled ?? source.enabled,
      },
    );
    return RemoteScanSource.fromJson(_jsonObject(response));
  }

  Future<RemoteScanSource> scanNow(String id) async {
    final response = await _request('POST', '/api/scan-sources/$id/scan');
    return RemoteScanSource.fromJson(_jsonObject(response));
  }

  Future<void> deleteSource(String id) async {
    await _request('DELETE', '/api/scan-sources/$id');
  }

  Future<List<RemoteScannedTrack>> listTracks(
    String id, {
    int limit = 200,
  }) async {
    final response = await _request(
      'GET',
      '/api/scan-sources/$id/tracks?limit=$limit',
    );
    return (jsonDecode(response.body) as List<dynamic>)
        .map(
          (value) => RemoteScannedTrack.fromJson(
            (value as Map).cast<String, dynamic>(),
          ),
        )
        .toList(growable: false);
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    var session = await _authRepository.currentSession();
    if (session == null) throw StateError('请先登录账号。');
    var response = await _send(method, path, session.token, body);
    if (response.statusCode == 401) {
      session = await _authRepository.currentSession(forceRefresh: true);
      if (session == null) throw StateError('登录已过期，请重新登录。');
      response = await _send(method, path, session.token, body);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_errorMessage(response));
    }
    return response;
  }

  Future<http.Response> _send(
    String method,
    String path,
    String token,
    Map<String, dynamic>? body,
  ) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final encoded = body == null ? null : jsonEncode(body);
    try {
      return await switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(uri, headers: headers, body: encoded),
        'PUT' => _client.put(uri, headers: headers, body: encoded),
        'DELETE' => _client.delete(uri, headers: headers),
        _ => throw ArgumentError.value(method, 'method'),
      }.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw StateError('连接后端超时，请检查服务地址和运行状态。');
    } on http.ClientException catch (error) {
      throw StateError('无法连接后端：${error.message}');
    }
  }

  static Map<String, dynamic> _jsonObject(http.Response response) =>
      (jsonDecode(response.body) as Map).cast<String, dynamic>();

  static String _errorMessage(http.Response response) {
    try {
      return (_jsonObject(response)['message'] as String?) ??
          '请求失败（${response.statusCode}）';
    } catch (_) {
      return '请求失败（${response.statusCode}）';
    }
  }
}
