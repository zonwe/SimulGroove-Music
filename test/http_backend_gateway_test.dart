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
    final gateway = HttpBackendGateway(
      baseUrl: 'http://localhost:5080',
      client: client,
    );

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
      expect(body['deletions'], hasLength(1));
      return http.Response(
        jsonEncode({
          'playlists': body['playlists'],
          'likedTracks': body['likedTracks'],
          'deletions': body['deletions'],
        }),
        200,
      );
    });
    final gateway = HttpBackendGateway(
      baseUrl: 'http://localhost:5080',
      client: client,
    );
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

    final deletion = BackendDeletion(
      entityType: SyncEntityType.playlist,
      remoteKey: 'playlist-deleted',
      deletedAt: DateTime.utc(2026, 8, 1),
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
      const [],
      [deletion],
    );

    expect(result.playlists.single.remoteId, 'playlist-1');
    expect(result.likedTracks.single.uri, track.uri);
    expect(result.deletions.single.remoteKey, deletion.remoteKey);
  });

  test('未配置服务器地址时给出可操作的中文引导', () async {
    final gateway = HttpBackendGateway(
      client: MockClient((_) async => fail('未配置地址时不应发出任何请求')),
    );

    await expectLater(
      gateway.signIn(username: 'user@example.com', password: 'secret'),
      throwsA(
        isA<BackendException>().having(
          (error) => error.message,
          'message',
          '尚未配置服务器地址，请在账号页填写后端地址。',
        ),
      ),
    );
  });

  test('运行时地址解析器会覆盖编译期默认值', () async {
    final gateway = HttpBackendGateway(
      readBaseUrl: () async => 'http://runtime-host:5080/',
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          'http://runtime-host:5080/api/auth/login',
        );
        return http.Response(
          jsonEncode({
            'token': 'access-token',
            'refreshToken': 'refresh-token',
            'expiresAt': '2026-08-01T10:30:00Z',
            'account': {
              'remoteId': 'account-user',
              'username': 'user',
              'displayName': 'user',
              'avatarUri': null,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final session = await gateway.signIn(username: 'user', password: 'secret');

    expect(session.token, 'access-token');
  });
}
