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
  HttpOnlineMusicGateway({
    String? baseUrl,
    http.Client? client,
    BackendBaseUrlReader? readBaseUrl,
  }) : _fixedBaseUrl = baseUrl == null
           ? null
           : normalizeBackendBaseUrl(baseUrl),
       _client = client ?? http.Client(),
       _baseUrlReader = readBaseUrl;

  static const _timeout = Duration(seconds: 15);

  // 固定地址用于测试；生产路径每次请求读取 AppSettings，
  // 与 HttpBackendGateway 保持一致的地址解析语义。
  final String? _fixedBaseUrl;
  final BackendBaseUrlReader? _baseUrlReader;
  final http.Client _client;

  Future<String> _requireBaseUrl() async {
    if (_fixedBaseUrl != null) return _fixedBaseUrl;
    final resolved = normalizeBackendBaseUrl(
      await _baseUrlReader?.call() ?? defaultBackendBaseUrl,
    );
    if (resolved.isEmpty) {
      throw const OnlineMusicException(
        '尚未配置服务器地址，请先在账号页登录后端。',
        code: 'online_music_server_not_configured',
      );
    }
    return resolved;
  }

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
    final baseUrl = await _requireBaseUrl();
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
      url: Uri.parse('$baseUrl/').resolve(playbackUrl),
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
    final baseUrl = await _requireBaseUrl();
    final provider = Uri.encodeComponent(track.provider);
    final trackId = Uri.encodeComponent(track.trackId);
    return OnlinePlaybackSource(
      url: Uri.parse(
        '$baseUrl/api/online-music/tracks/$provider/$trackId/download',
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
    // 歌词是可选增强：上游没有歌词（404）时返回 null 属正常降级，
    // 由 UI 展示"暂无歌词"，不视为错误。
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
    // 封面同样是可选增强：404 时返回 null 由 UI 显示占位图，不视为错误。
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
    final baseUrl = await _requireBaseUrl();
    try {
      final uri = Uri.parse('$baseUrl$path');
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
      // 服务端把"熔断恢复中"和"来源全挂"单独区分出来：前者只需等一会儿，
      // 后者可以换关键词，笼统的"服务不可用"会让用户无从判断。
      'online_music_circuit_open' => '在线音乐服务正在恢复中，请稍后重试。',
      'online_music_sources_unavailable' => '所选音乐来源暂时都不可用，请稍后重试。',
      'online_music_track_unavailable' => '该歌曲暂时没有可播放的音源。',
      'online_music_playback_unavailable' => '该歌曲音源已失效，请重新选择。',
      'online_music_upstream_timeout' => '在线音乐来源响应超时，请稍后重试。',
      'online_music_playback_expired' => '播放票据已过期，请重新播放。',
      'online_music_playback_not_found' => '播放票据不存在，请重新播放。',
      'online_music_asset_too_large' => '在线音乐资源超过大小限制。',
      _ => message,
    };
    throw OnlineMusicException(
      localizedMessage ??
          _unauthorizedMessage(response) ??
          '在线音乐请求失败（HTTP ${response.statusCode}）。',
      statusCode: response.statusCode,
      code: code,
    );
  }

  /// 401/403 通常没有 JSON 响应体，兜底给出可操作的中文提示。
  static String? _unauthorizedMessage(http.Response response) =>
      switch (response.statusCode) {
        401 || 403 => '登录状态已失效，请重新登录。',
        _ => null,
      };

  static Map<String, dynamic> _jsonObject(http.Response response) =>
      (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
          .cast<String, dynamic>();

  static String _assetPath(OnlineTrack track, String asset) {
    final provider = Uri.encodeComponent(track.provider);
    final trackId = Uri.encodeComponent(track.trackId);
    return '/api/online-music/tracks/$provider/$trackId/$asset';
  }
}
