import 'dart:typed_data';

import '../auth/auth_repository.dart';
import '../auth/backend_gateway.dart';
import 'online_music_error.dart';
import 'online_music_gateway.dart';
import 'online_track.dart';

abstract interface class OnlineMusicSearchRepository {
  Future<OnlineMusicSearchResult> search(String query, {String? cursor});
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track);
  Future<String?> loadLyrics(OnlineTrack track);
  Future<Uint8List?> loadArtwork(OnlineTrack track);
}

abstract interface class OnlineMusicDownloadRepository {
  Future<OnlinePlaybackSource> prepareDownload(OnlineTrack track);
}

class AuthenticatedOnlineMusicRepository
    implements OnlineMusicSearchRepository, OnlineMusicDownloadRepository {
  AuthenticatedOnlineMusicRepository(this._auth, this._gateway);

  final AuthRepository _auth;
  final OnlineMusicGateway _gateway;

  @override
  Future<OnlineMusicSearchResult> search(String query, {String? cursor}) async {
    var session = await _requireSession();

    try {
      return await _gateway.search(session, query: query, cursor: cursor);
    } on OnlineMusicException catch (error) {
      if (!error.isUnauthorized) rethrow;
      session = await _requireSession(forceRefresh: true);
      return _gateway.search(session, query: query, cursor: cursor);
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

  @override
  Future<OnlinePlaybackSource> prepareDownload(OnlineTrack track) async {
    if (!track.playable || !track.capabilities.contains('playback')) {
      throw const OnlineMusicException(
        '当前在线音乐来源不支持下载这首歌曲。',
        code: 'online_music_not_playable',
      );
    }
    final gateway = _gateway;
    if (gateway is! OnlineMusicDownloadGateway) {
      return preparePlayback(track);
    }
    final downloadGateway = gateway as OnlineMusicDownloadGateway;
    var session = await _requireSession();
    try {
      return await downloadGateway.requestDownload(session, track);
    } on OnlineMusicException catch (error) {
      if (!error.isUnauthorized) rethrow;
      session = await _requireSession(forceRefresh: true);
      return downloadGateway.requestDownload(session, track);
    }
  }

  @override
  Future<String?> loadLyrics(OnlineTrack track) async {
    if (!track.capabilities.contains('lyrics')) return null;
    var session = await _requireSession();
    try {
      return await _gateway.fetchLyrics(session, track);
    } on OnlineMusicException catch (error) {
      if (!error.isUnauthorized) rethrow;
      session = await _requireSession(forceRefresh: true);
      return _gateway.fetchLyrics(session, track);
    }
  }

  @override
  Future<Uint8List?> loadArtwork(OnlineTrack track) async {
    if (!track.capabilities.contains('artwork')) return null;
    var session = await _requireSession();
    try {
      return await _gateway.fetchArtwork(session, track);
    } on OnlineMusicException catch (error) {
      if (!error.isUnauthorized) rethrow;
      session = await _requireSession(forceRefresh: true);
      return _gateway.fetchArtwork(session, track);
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
