import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend_gateway.dart';

class HttpBackendGateway implements BackendGateway {
  HttpBackendGateway({String? baseUrl, http.Client? client})
    : _baseUrl = (baseUrl ?? defaultBackendBaseUrl).replaceFirst(
        RegExp(r'/$'),
        '',
      ),
      _client = client ?? http.Client();

  static const _timeout = Duration(seconds: 15);

  final String _baseUrl;
  final http.Client _client;

  @override
  Future<BackendSession> signIn({
    required String username,
    required String password,
  }) async {
    final response = await _send(
      'POST',
      '/api/auth/login',
      body: {'username': username, 'password': password},
    );
    _ensureSuccess(response);
    return BackendSession.fromJson(_jsonObject(response));
  }

  @override
  Future<BackendSession> refreshSession(String refreshToken) async {
    final response = await _send(
      'POST',
      '/api/auth/refresh',
      body: {'refreshToken': refreshToken},
    );
    _ensureSuccess(response);
    return BackendSession.fromJson(_jsonObject(response));
  }

  @override
  Future<void> signOut(String token) async {
    final response = await _send('POST', '/api/auth/logout', token: token);
    if (response.statusCode != 401) _ensureSuccess(response);
  }

  @override
  Future<BackendLibrary> syncLibrary(
    BackendSession session,
    List<BackendPlaylist> playlists,
    List<BackendTrack> likedTracks,
  ) async {
    final response = await _send(
      'POST',
      '/api/playlists/sync',
      token: session.token,
      body: {
        'playlists': playlists
            .map((playlist) => playlist.toJson())
            .toList(growable: false),
        'likedTracks': likedTracks
            .map((track) => track.toJson())
            .toList(growable: false),
      },
    );
    _ensureSuccess(response);
    final json = _jsonObject(response);
    return BackendLibrary(
      playlists: (json['playlists'] as List<dynamic>)
          .map(
            (value) => BackendPlaylist.fromJson(
              (value as Map).cast<String, dynamic>(),
            ),
          )
          .toList(growable: false),
      likedTracks: (json['likedTracks'] as List<dynamic>)
          .map(
            (value) =>
                BackendTrack.fromJson((value as Map).cast<String, dynamic>()),
          )
          .toList(growable: false),
    );
  }

  Future<http.Response> _send(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final encoded = body == null ? null : jsonEncode(body);
    try {
      return await switch (method) {
        'POST' => _client.post(
          Uri.parse('$_baseUrl$path'),
          headers: headers,
          body: encoded,
        ),
        _ => throw ArgumentError.value(method, 'method'),
      }.timeout(_timeout);
    } on TimeoutException {
      throw const BackendException('连接后端超时，请检查服务地址和运行状态。');
    } on http.ClientException catch (error) {
      throw BackendException('无法连接后端：${error.message}');
    }
  }

  static void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String? code;
    String? message;
    try {
      final json = _jsonObject(response);
      code = json['code'] as String?;
      message = json['message'] as String?;
    } catch (_) {
      // Non-JSON error responses fall back to the status code below.
    }
    final localizedMessage = switch (code) {
      'invalid_credentials' => '账号或密码错误。',
      'invalid_refresh_token' => '登录已过期，请重新登录。',
      'invalid_request' => '请求参数不完整。',
      _ => message,
    };
    throw BackendException(
      localizedMessage ?? '后端请求失败（HTTP ${response.statusCode}）。',
      statusCode: response.statusCode,
      code: code,
    );
  }

  static Map<String, dynamic> _jsonObject(http.Response response) =>
      (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
          .cast<String, dynamic>();
}
