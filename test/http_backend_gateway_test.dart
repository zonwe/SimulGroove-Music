import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_music/core/auth/backend_gateway.dart';
import 'package:flutter_music/core/auth/http_backend_gateway.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('登录响应会解析为完整会话', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/auth/login');
      expect(jsonDecode(request.body), {
        'username': 'user@example.com',
        'password': 'secret',
      });
      return http.Response(
        jsonEncode({
          'token': 'access-token',
          'refreshToken': 'refresh-token',
          'expiresAt': '2026-08-01T10:30:00Z',
          'account': {
            'remoteId': 'account-user@example.com',
            'username': 'user@example.com',
            'displayName': 'user',
            'avatarUri': null,
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final gateway = HttpBackendGateway(
      baseUrl: 'http://localhost:5080/',
      client: client,
    );

    final session = await gateway.signIn(
      username: 'user@example.com',
      password: 'secret',
    );

    expect(session.token, 'access-token');
    expect(session.refreshToken, 'refresh-token');
    expect(session.account.displayName, 'user');
  });

  test('无效密码映射为可展示的中文错误', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'code': 'invalid_credentials',
          'message': 'Invalid username or password.',
        }),
        401,
      ),
    );
    final gateway = HttpBackendGateway(client: client);

    await expectLater(
      gateway.signIn(username: 'user@example.com', password: 'wrong'),
      throwsA(
        isA<BackendException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.message, 'message', '账号或密码错误。'),
      ),
    );
  });

  test('同步会发送歌单和喜欢歌曲并解析返回值', () async {
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer access-token');
      final body = (jsonDecode(request.body) as Map).cast<String, dynamic>();
      expect(body['playlists'], hasLength(1));
      expect(body['likedTracks'], hasLength(1));
      return http.Response(
        jsonEncode({
          'playlists': body['playlists'],
          'likedTracks': body['likedTracks'],
        }),
        200,
      );
    });
    final gateway = HttpBackendGateway(client: client);
    final session = BackendSession(
      token: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      account: const BackendAccount(
        remoteId: 'account-user',
        username: 'user',
        displayName: 'user',
      ),
    );
    const track = BackendTrack(
      uri: 'file:///music/song.mp3',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
    );

    final result = await gateway.syncLibrary(
      session,
      [
        BackendPlaylist(
          remoteId: 'playlist-1',
          name: 'Test',
          updatedAt: DateTime.utc(2026, 8, 1),
          tracks: const [track],
        ),
      ],
      const [track],
    );

    expect(result.playlists.single.remoteId, 'playlist-1');
    expect(result.likedTracks.single.uri, track.uri);
  });
}
