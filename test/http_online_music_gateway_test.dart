import 'dart:convert';

import 'package:flutter_music/core/auth/backend_gateway.dart';
import 'package:flutter_music/core/online_music/http_online_music_gateway.dart';
import 'package:flutter_music/core/online_music/online_music_error.dart';
import 'package:flutter_music/core/online_music/online_track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final session = BackendSession(
    token: 'access-token',
    refreshToken: 'refresh-token',
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
    account: const BackendAccount(
      remoteId: 'account-user',
      username: 'user',
      displayName: 'User',
    ),
  );

  test('在线搜索发送 Bearer Token 并解析部分结果', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/online-music/search');
      expect(request.headers['authorization'], 'Bearer access-token');
      expect(jsonDecode(request.body), {
        'query': '夜曲',
        'sources': <String>[],
        'limit': 20,
        'cursor': null,
      });
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'items': [
              {
                'provider': 'source-a',
                'trackId': 'track-1',
                'title': '夜曲',
                'artists': ['Artist'],
                'album': 'Album',
                'durationMs': 238000,
                'artworkUrl': null,
                'playable': true,
                'capabilities': ['playback'],
              },
            ],
            'partial': true,
            'warnings': [
              {
                'provider': 'source-b',
                'code': 'online_music_source_unavailable',
                'message': '该来源暂时不可用。',
              },
            ],
            'nextCursor': null,
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final gateway = HttpOnlineMusicGateway(client: client);

    final result = await gateway.search(session, query: '夜曲');

    expect(result.items.single.id, 'source-a:track-1');
    expect(result.partial, isTrue);
    expect(result.warnings.single.provider, 'source-b');
  });

  test('稳定错误码会映射为中文提示', () async {
    final gateway = HttpOnlineMusicGateway(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'online_music_rate_limited',
            'message': 'Too many requests.',
          }),
          429,
        ),
      ),
    );

    await expectLater(
      gateway.search(session, query: 'Song'),
      throwsA(
        isA<OnlineMusicException>()
            .having((error) => error.statusCode, 'statusCode', 429)
            .having((error) => error.message, 'message', '搜索太频繁，请稍后再试。'),
      ),
    );
  });

  test('播放票据转换为带 Bearer Token 的受控音源', () async {
    final gateway = HttpOnlineMusicGateway(
      baseUrl: 'http://music-api.test:5080',
      client: MockClient((request) async {
        expect(
          request.url.path,
          '/api/online-music/tracks/source-a/track-1/playback',
        );
        expect(request.headers['authorization'], 'Bearer access-token');
        return http.Response(
          jsonEncode({
            'playbackUrl': '/api/online-music/playback/opaque-ticket',
            'expiresAt': '2026-08-08T12:05:00Z',
            'mimeType': 'audio/mpeg',
          }),
          200,
        );
      }),
    );

    final source = await gateway.requestPlayback(
      session,
      const OnlineTrack(
        provider: 'source-a',
        trackId: 'track-1',
        title: 'Song',
        artists: ['Artist'],
        album: 'Album',
        playable: true,
        capabilities: {'playback'},
      ),
    );

    expect(
      source.url.toString(),
      'http://music-api.test:5080/api/online-music/playback/opaque-ticket',
    );
    expect(source.headers['Authorization'], 'Bearer access-token');
    expect(source.mimeType, 'audio/mpeg');
  });
}
