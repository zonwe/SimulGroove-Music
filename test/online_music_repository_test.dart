import 'dart:typed_data';

import 'package:flutter_music/core/auth/auth_repository.dart';
import 'package:flutter_music/core/auth/backend_gateway.dart';
import 'package:flutter_music/core/online_music/online_music_error.dart';
import 'package:flutter_music/core/online_music/online_music_gateway.dart';
import 'package:flutter_music/core/online_music/online_music_repository.dart';
import 'package:flutter_music/core/online_music/online_track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('401 时刷新会话一次并重试搜索', () async {
    final auth = _FakeAuthRepository();
    final gateway = _RetryGateway();
    final repository = AuthenticatedOnlineMusicRepository(auth, gateway);

    final result = await repository.search('Song', cursor: 'next-page');

    expect(auth.forceRefreshCount, 1);
    expect(gateway.tokens, ['expired-token', 'refreshed-token']);
    expect(gateway.cursors, ['next-page', 'next-page']);
    expect(result.items.single.title, 'Song');
  });

  test('播放票据请求同样只刷新并重试一次', () async {
    final auth = _FakeAuthRepository();
    final gateway = _RetryGateway();
    final repository = AuthenticatedOnlineMusicRepository(auth, gateway);

    final source = await repository.preparePlayback(
      const OnlineTrack(
        provider: 'source-a',
        trackId: '1',
        title: 'Song',
        artists: ['Artist'],
        album: 'Album',
        playable: true,
        capabilities: {'playback'},
      ),
    );

    expect(auth.forceRefreshCount, 1);
    expect(gateway.tokens, ['expired-token', 'refreshed-token']);
    expect(source.url.path, '/api/online-music/playback/ticket');
  });
}

class _FakeAuthRepository implements AuthRepository {
  var forceRefreshCount = 0;

  @override
  Future<BackendSession?> currentSession({bool forceRefresh = false}) async {
    if (forceRefresh) forceRefreshCount++;
    return BackendSession(
      token: forceRefresh ? 'refreshed-token' : 'expired-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      account: const BackendAccount(
        remoteId: 'account-user',
        username: 'user',
        displayName: 'User',
      ),
    );
  }

  @override
  Future<void> signIn({required String username, required String password}) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<SyncResult> syncNow() => throw UnimplementedError();
}

class _RetryGateway implements OnlineMusicGateway {
  final tokens = <String>[];
  final cursors = <String?>[];

  @override
  Future<OnlineMusicSearchResult> search(
    BackendSession session, {
    required String query,
    List<String> sources = const [],
    int limit = 20,
    String? cursor,
  }) async {
    tokens.add(session.token);
    cursors.add(cursor);
    if (tokens.length == 1) {
      throw const OnlineMusicException('Unauthorized', statusCode: 401);
    }
    return const OnlineMusicSearchResult(
      items: [
        OnlineTrack(
          provider: 'source-a',
          trackId: '1',
          title: 'Song',
          artists: ['Artist'],
          album: 'Album',
          playable: true,
          capabilities: {'playback'},
        ),
      ],
      partial: false,
      warnings: [],
    );
  }

  @override
  Future<OnlinePlaybackSource> requestPlayback(
    BackendSession session,
    OnlineTrack track,
  ) async {
    tokens.add(session.token);
    if (tokens.length == 1) {
      throw const OnlineMusicException('Unauthorized', statusCode: 401);
    }
    return OnlinePlaybackSource(
      url: Uri.parse('http://localhost:5080/api/online-music/playback/ticket'),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 2)),
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
  }

  @override
  Future<String?> fetchLyrics(
    BackendSession session,
    OnlineTrack track,
  ) async => null;

  @override
  Future<Uint8List?> fetchArtwork(
    BackendSession session,
    OnlineTrack track,
  ) async => null;
}
