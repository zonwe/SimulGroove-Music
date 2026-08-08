import '../auth/auth_repository.dart';
import '../auth/backend_gateway.dart';
import 'online_music_error.dart';
import 'online_music_gateway.dart';
import 'online_track.dart';

abstract interface class OnlineMusicSearchRepository {
  Future<OnlineMusicSearchResult> search(String query);
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track);
}

class AuthenticatedOnlineMusicRepository
    implements OnlineMusicSearchRepository {
  AuthenticatedOnlineMusicRepository(this._auth, this._gateway);

  final AuthRepository _auth;
  final OnlineMusicGateway _gateway;

  @override
  Future<OnlineMusicSearchResult> search(String query) async {
    var session = await _requireSession();

    try {
      return await _gateway.search(session, query: query);
    } on OnlineMusicException catch (error) {
      if (!error.isUnauthorized) rethrow;
      session = await _requireSession(forceRefresh: true);
      return _gateway.search(session, query: query);
    }
  }

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) async {
    if (!track.playable || !track.capabilities.contains('playback')) {
      throw const OnlineMusicException(
        '当前在线音乐来源不支持播放这首歌曲。',
        code: 'online_music_not_playable',
      );
    }
    var session = await _requireSession();
    try {
      return await _gateway.requestPlayback(session, track);
    } on OnlineMusicException catch (error) {
      if (!error.isUnauthorized) rethrow;
      session = await _requireSession(forceRefresh: true);
      return _gateway.requestPlayback(session, track);
    }
  }

  Future<BackendSession> _requireSession({bool forceRefresh = false}) async {
    final session = await _auth.currentSession(forceRefresh: forceRefresh);
    if (session == null) {
      throw OnlineMusicException(
        forceRefresh ? '登录已过期，请重新登录。' : '请先登录账号，再使用在线音乐。',
        statusCode: 401,
        code: 'online_music_auth_required',
      );
    }
    return session;
  }
}
