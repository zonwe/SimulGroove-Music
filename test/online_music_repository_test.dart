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

  test('未登录时直接匿名搜索且不强制刷新会话', () async {
    final auth = _FakeAuthRepository(hasSession: false);
    final gateway = _RetryGateway(failFirst: false);
    final repository = AuthenticatedOnlineMusicRepository(auth, gateway);

    final result = await repository.search('Song');

    expect(auth.forceRefreshCount, 0);
    expect(gateway.tokens, [null]);
    expect(gateway.cursors, [null]);
    expect(result.items.single.title, 'Song');
  });

  test('会话刷新后仍没有会话时退回匿名搜索', () async {
    final auth = _FakeAuthRepository(refreshDropsSession: true);
    final gateway = _RetryGateway();
    final repository = AuthenticatedOnlineMusicRepository(auth, gateway);

    final result = await repository.search('Song');

    expect(auth.forceRefreshCount, 1);
    expect(gateway.tokens, ['expired-token', null]);
    expect(result.items.single.title, 'Song');
  });

  test('会话读取失败时仍退回匿名搜索', () async {
    final gateway = _RetryGateway(failFirst: false);
    final repository = AuthenticatedOnlineMusicRepository(
      _ThrowingAuthRepository(),
      gateway,
    );

    final result = await repository.search('Song');

    expect(gateway.tokens, [null]);
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
  _FakeAuthRepository({
    this.hasSession = true,
    this.refreshDropsSession = false,
  });

  final bool hasSession;
  final bool refreshDropsSession;
  var forceRefreshCount = 0;

  @override
  Future<BackendSession?> currentSession({bool forceRefresh = false}) async {
    if (!hasSession) return null;
    if (forceRefresh) {
      forceRefreshCount++;
      if (refreshDropsSession) return null;
    }
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

class _ThrowingAuthRepository implements AuthRepository {
  @override
  Future<BackendSession?> currentSession({bool forceRefresh = false}) async =>
      throw const BackendException('无法连接后端服务。');

  @override
  Future<void> signIn({required String username, required String password}) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<SyncResult> syncNow() => throw UnimplementedError();
}

class _RetryGateway implements OnlineMusicGateway {
  _RetryGateway({this.failFirst = true});

  final bool failFirst;
  final tokens = <String?>[];
  final cursors = <String?>[];

  @override
  Future<OnlineMusicSearchResult> search(
    BackendSession? session, {
    required String query,
    List<String> sources = const [],
    int limit = 20,
    String? cursor,
  }) async {
    tokens.add(session?.token);
    cursors.add(cursor);
    if (failFirst && tokens.length == 1) {
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
