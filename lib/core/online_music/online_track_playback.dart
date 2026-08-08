import 'package:flutter/foundation.dart';

import '../player/music_audio_handler.dart';
import 'online_music_repository.dart';
import 'online_track.dart';

abstract interface class OnlineTrackPlayback {
  bool get supported;
  Future<void> play(OnlineTrack track);
}

class DefaultOnlineTrackPlayback implements OnlineTrackPlayback {
  DefaultOnlineTrackPlayback(this._repository, this._audioHandler);

  final OnlineMusicSearchRepository _repository;
  final MusicAudioHandler _audioHandler;

  @override
  bool get supported => !kIsWeb;

  @override
  Future<void> play(OnlineTrack track) async {
    if (!supported) {
      throw UnsupportedError('Web 暂不支持需要认证请求头的在线播放。');
    }
    final source = await _repository.preparePlayback(track);
    await _audioHandler.playOnlineTrack(
      id: track.id,
      title: track.title,
      artist: track.artists.join('、'),
      album: track.album,
      durationMs: track.durationMs,
      provider: track.provider,
      trackId: track.trackId,
      uri: source.url,
      headers: source.headers,
    );
  }
}
