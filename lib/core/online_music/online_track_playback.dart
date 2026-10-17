import 'dart:async';

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
  int _request = 0;

  @override
  bool get supported => !kIsWeb;

  @override
  Future<void> play(OnlineTrack track) async {
    if (!supported) {
      throw UnsupportedError('Web 暂不支持需要认证请求头的在线播放。');
    }
    final request = ++_request;
    final queueRevision = _audioHandler.queueRevision;
    final source = await _repository.preparePlayback(track);
    if (request != _request || queueRevision != _audioHandler.queueRevision) {
      return;
    }
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
    if (request == _request) unawaited(_loadMetadata(track, request));
  }

  Future<void> _loadMetadata(OnlineTrack track, int request) async {
    final (lyrics, artwork) = await (
      _optionalLyrics(track),
      _optionalArtwork(track),
    ).wait;
    if (request != _request) return;
    await _audioHandler.updateOnlineTrackMetadata(
      id: track.id,
      lyrics: lyrics,
      artwork: artwork,
    );
  }

  Future<String?> _optionalLyrics(OnlineTrack track) async {
    try {
      return await _repository.loadLyrics(track);
    } catch (_) {
      // 歌词是可选增强：加载失败时按"暂无歌词"降级，不阻塞播放。
      return null;
    }
  }

  Future<Uint8List?> _optionalArtwork(OnlineTrack track) async {
    try {
      return await _repository.loadArtwork(track);
    } catch (_) {
      // 封面是可选增强：加载失败时由 UI 显示占位图，不阻塞播放。
      return null;
    }
  }
}
