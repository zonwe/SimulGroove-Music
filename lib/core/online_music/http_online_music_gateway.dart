import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../auth/backend_gateway.dart';
import 'online_music_error.dart';
import 'online_music_gateway.dart';
import 'online_track.dart';

class HttpOnlineMusicGateway
    implements OnlineMusicGateway, OnlineMusicDownloadGateway {
  HttpOnlineMusicGateway({String? baseUrl, http.Client? client})
    : _baseUrl = (baseUrl ?? defaultBackendBaseUrl).replaceFirst(
        RegExp(r'/$'),
        '',
      ),
      _client = client ?? http.Client();

  static const _timeout = Duration(seconds: 15);

  final String _baseUrl;
  final http.Client _client;

  @override
  Future<OnlineMusicSearchResult> search(
    BackendSession session, {
    required String query,
    List<String> sources = const [],
    int limit = 20,
    String? cursor,
  }) async {
    final response = await _send(
      '/api/online-music/search',
      token: session.token,
      body: {
        'query': query,
        'sources': sources,
        'limit': limit,
        'cursor': cursor,
      },
    );
    _ensureSuccess(response);
    return OnlineMusicSearchResult.fromJson(_jsonObject(response));
  }

  @override
  Future<OnlinePlaybackSource> requestPlayback(
    BackendSession session,
    OnlineTrack track,
  ) async {
    final provider = Uri.encodeComponent(track.provider);
    final trackId = Uri.encodeComponent(track.trackId);
    final response = await _send(
      '/api/online-music/tracks/$provider/$trackId/playback',
      token: session.token,
    );
    _ensureSuccess(response);
    final json = _jsonObject(response);
    final playbackUrl = json['playbackUrl'] as String?;
    final expiresAt = json['expiresAt'] as String?;
    if (playbackUrl == null ||
        !playbackUrl.startsWith('/api/online-music/playback/') ||
        expiresAt == null) {
      throw const OnlineMusicException(
        '服务端返回了无效的播放票据。',
        code: 'online_music_invalid_response',
      );
    }
    return OnlinePlaybackSource(
      url: Uri.parse('$_baseUrl/').resolve(playbackUrl),
      expiresAt: DateTime.parse(expiresAt).toUtc(),
      mimeType: json['mimeType'] as String?,
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
  }

  @override
  Future<OnlinePlaybackSource> requestDownload(
    BackendSession session,
    OnlineTrack track,
  ) async {
    final provider = Uri.encodeComponent(track.provider);
    final trackId = Uri.encodeComponent(track.trackId);
    return OnlinePlaybackSource(
      url: Uri.parse(
        '$_baseUrl/api/online-music/tracks/$provider/$trackId/download',
      ),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
  }

  @override
  Future<String?> fetchLyrics(BackendSession session, OnlineTrack track) async {
    if (!track.capabilities.contains('lyrics')) return null;
    final response = await _send(
      _assetPath(track, 'lyrics'),
      token: session.token,
      method: 'GET',
    );
    if (response.statusCode == 404) return null;
    _ensureSuccess(response);
    final lyrics = _jsonObject(response)['lyrics'] as String?;
    if (lyrics == null || lyrics.trim().isEmpty) return null;
    return lyrics;
  }

  @override
  Future<Uint8List?> fetchArtwork(
    BackendSession session,
    OnlineTrack track,
  ) async {
    if (!track.capabilities.contains('artwork') || track.artworkUrl == null) {
      return null;
    }
    final expectedPath = _assetPath(track, 'cover');
    if (track.artworkUrl != expectedPath) {
      throw const OnlineMusicException(
        '服务端返回了无效的封面地址。',
        code: 'online_music_invalid_response',
      );
    }
    final response = await _send(
      expectedPath,
      token: session.token,
      method: 'GET',
    );
    if (response.statusCode == 404) return null;
    _ensureSuccess(response);
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().startsWith('image/') ||
        response.bodyBytes.isEmpty ||
        response.bodyBytes.length > 2 * 1024 * 1024) {
      throw const OnlineMusicException(
        '服务端返回了无效的封面。',
        code: 'online_music_invalid_response',
      );
    }
    return response.bodyBytes;
  }

  Future<http.Response> _send(
    String path, {
    required String token,
    Map<String, dynamic>? body,
    String method = 'POST',
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final headers = {
        'Accept': method == 'GET' ? '*/*' : 'application/json',
        'Authorization': 'Bearer $token',
        if (method != 'GET') 'Content-Type': 'application/json',
      };
      final request = method == 'GET'
          ? _client.get(uri, headers: headers)
          : _client.post(
              uri,
              headers: headers,
              body: body == null ? null : jsonEncode(body),
            );
      return await request.timeout(_timeout);
    } on TimeoutException {
      throw const OnlineMusicException(
        '在线音乐服务响应超时，请稍后重试。',
        code: 'online_music_upstream_timeout',
      );
    } on http.ClientException {
      throw const OnlineMusicException('无法连接在线音乐服务，请检查网络。');
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
      // Non-JSON failures use a stable client-side fallback below.
    }
    final localizedMessage = switch (code) {
      'online_music_invalid_request' => '搜索内容或来源无效。',
      'online_music_rate_limited' => '搜索太频繁，请稍后再试。',
      'online_music_source_unavailable' => '在线音乐服务暂时不可用。',
      'online_music_upstream_timeout' => '在线音乐来源响应超时，请稍后重试。',
      'online_music_playback_expired' => '播放票据已过期，请重新播放。',
      'online_music_playback_not_found' => '播放票据不存在，请重新播放。',
      'online_music_asset_too_large' => '在线音乐资源超过大小限制。',
      _ => message,
    };
    throw OnlineMusicException(
      localizedMessage ?? '在线音乐请求失败（HTTP ${response.statusCode}）。',
      statusCode: response.statusCode,
      code: code,
    );
  }

  static Map<String, dynamic> _jsonObject(http.Response response) =>
      (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
          .cast<String, dynamic>();

  static String _assetPath(OnlineTrack track, String asset) {
    final provider = Uri.encodeComponent(track.provider);
    final trackId = Uri.encodeComponent(track.trackId);
    return '/api/online-music/tracks/$provider/$trackId/$asset';
  }
}
