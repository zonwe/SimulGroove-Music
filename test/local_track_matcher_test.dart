import 'dart:convert';

import 'package:flutter_music/core/auth/backend_gateway.dart';
import 'package:flutter_music/core/auth/local_track_matcher.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

const _fingerprint =
    'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _otherFingerprint =
    'sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

/// 32 字节的 PBKDF2 输出即可；这里只需要一个能通过 base64Url 解码的密钥。
final _matchKey = base64Url.encode(List<int>.filled(32, 7));

void main() {
  group('URI 与在线曲目', () {
    test('URI 完全一致时命中同一台设备的曲目', () {
      final track = _local(
        'android',
        uri: 'content://media/external/audio/media/7',
        sourceType: 'android_media_store',
      );
      final matcher = LocalTrackMatcher([track], trackMatchKey: _matchKey);

      expect(
        matcher.find(_remote(uri: 'content://media/external/audio/media/7')),
        same(track),
      );
    });

    test('在线曲目按稳定 id 命中本地已下载或占位曲目', () {
      final track = _local(
        'online:netease:123',
        uri: 'online-music://track/netease/123',
        sourceType: 'online',
      );
      final matcher = LocalTrackMatcher([track], trackMatchKey: _matchKey);

      expect(
        matcher.find(_remote(uri: 'online-music://track/netease/123')),
        same(track),
      );
      expect(
        onlineMusicTrackId(Uri.parse('online-music://track/netease/123')),
        'online:netease:123',
      );
      expect(
        isOnlineMusicTrackUri(Uri.parse('online-music://track/netease/123')),
        isTrue,
      );
      expect(isOnlineMusicTrackUri(Uri.parse('file:///D:/a.mp3')), isFalse);
    });
  });

  group('盲匹配令牌', () {
    test('令牌唯一命中时不受 URI 与标签差异影响', () {
      final windows = _local(
        'windows',
        uri: 'file:///D:/Music/song.mp3',
        contentFingerprint: _fingerprint,
      );
      final android = _local(
        'android',
        uri: 'content://media/external/audio/media/9',
        sourceType: 'android_media_store',
        contentFingerprint: _otherFingerprint,
      );
      final matcher = LocalTrackMatcher([
        windows,
        android,
      ], trackMatchKey: _matchKey);
      final token = matcher.matchTokenFor(windows)!;

      expect(
        matcher.find(
          _remote(
            uri: 'file:///E:/Elsewhere/copied.flac',
            title: '另一个标题',
            matchToken: token,
          ),
        ),
        same(windows),
      );
    });

    test('相同内容存在两份副本时视为歧义，不任意选中', () {
      final first = _local(
        'first',
        uri: 'file:///D:/Music/song.mp3',
        contentFingerprint: _fingerprint,
      );
      final second = _local(
        'second',
        uri: 'file:///D:/Backup/song copy.mp3',
        contentFingerprint: _fingerprint,
      );
      final matcher = LocalTrackMatcher([
        first,
        second,
      ], trackMatchKey: _matchKey);

      expect(
        matcher.find(
          _remote(
            uri: 'file:///E:/Elsewhere/copied.flac',
            title: '完全不同的标题',
            matchToken: matcher.matchTokenFor(first),
          ),
        ),
        isNull,
      );
    });

    test('不可用曲目不参与匹配，但仍能被删除墓碑按令牌找到', () {
      final track = _local(
        'missing-file',
        uri: 'file:///D:/Music/gone.mp3',
        contentFingerprint: _fingerprint,
        isAvailable: false,
      );
      final matcher = LocalTrackMatcher([track], trackMatchKey: _matchKey);
      final token = matcher.matchTokenFor(track)!;

      expect(
        matcher.find(
          _remote(uri: 'file:///E:/Elsewhere/other.flac', matchToken: token),
        ),
        isNull,
      );
      expect(matcher.findKnownByMatchToken(token), same(track));
      expect(matcher.findKnownByUri('file:///D:/Music/gone.mp3'), same(track));
    });
  });

  group('元数据兜底', () {
    test('标题、艺术家、专辑一致时匹配', () {
      final track = _local('track', durationMs: 180000);
      final matcher = LocalTrackMatcher([track], trackMatchKey: _matchKey);

      expect(
        matcher.find(
          _remote(uri: 'file:///D:/Other/renamed.flac', durationMs: 181500),
        ),
        same(track),
      );
    });

    test('归一化忽略大小写与多余空白', () {
      final track = _local('track', title: '  Song   Title ');
      final matcher = LocalTrackMatcher([track], trackMatchKey: _matchKey);

      expect(
        matcher.find(
          _remote(uri: 'file:///D:/Other/renamed.flac', title: 'song title'),
        ),
        same(track),
      );
    });

    test('时长相差超过 3 秒不匹配', () {
      final track = _local('track', durationMs: 180000);
      final matcher = LocalTrackMatcher([track], trackMatchKey: _matchKey);

      expect(
        matcher.find(
          _remote(uri: 'file:///D:/Other/renamed.flac', durationMs: 183001),
        ),
        isNull,
      );
      expect(
        matcher.find(
          _remote(uri: 'file:///D:/Other/renamed.flac', durationMs: 183000),
        ),
        same(track),
      );
    });

    test('只有标题相同、艺术家与专辑都不同且文件名不同则不匹配', () {
      final track = _local('track');
      final matcher = LocalTrackMatcher([track], trackMatchKey: _matchKey);

      expect(
        matcher.find(
          _remote(
            uri: 'file:///D:/Other/renamed.flac',
            artist: 'Another Artist',
            album: 'Another Album',
          ),
        ),
        isNull,
      );
    });

    test('未知艺术家与未知专辑不构成有效匹配', () {
      final track = _local('track', artist: '未知艺术家', album: '未知专辑');
      final matcher = LocalTrackMatcher([track], trackMatchKey: _matchKey);

      expect(
        matcher.find(
          _remote(
            uri: 'file:///D:/Other/renamed.flac',
            artist: '未知艺术家',
            album: '未知专辑',
          ),
        ),
        isNull,
      );
    });

    test('文件名一致可以弥补标签差异', () {
      final track = _local(
        'track',
        uri: 'file:///D:/Music/Track%2005.flac',
        filePath: r'D:\Music\Track 05.flac',
        title: '本地标签标题',
        artist: '本地艺术家',
        album: '本地专辑',
      );
      final matcher = LocalTrackMatcher([track], trackMatchKey: _matchKey);

      expect(
        matcher.find(
          _remote(
            uri: 'file:///E:/Elsewhere/Track 05.flac',
            title: '云端标题',
            artist: '云端艺术家',
            album: '云端专辑',
          ),
        ),
        same(track),
      );
    });

    test('候选得分并列时视为歧义', () {
      final first = _local('first', uri: 'file:///D:/Music/one.mp3');
      final second = _local('second', uri: 'file:///D:/Music/two.mp3');
      final matcher = LocalTrackMatcher([
        first,
        second,
      ], trackMatchKey: _matchKey);

      expect(matcher.find(_remote(uri: 'file:///D:/Music/three.mp3')), isNull);
    });

    test('完全找不到依据时返回 null', () {
      final track = _local('track', title: 'Alpha', artist: 'A', album: 'B');
      final matcher = LocalTrackMatcher([track], trackMatchKey: _matchKey);

      expect(
        matcher.find(_remote(uri: 'file:///D:/Other/zzz.flac', title: 'Omega')),
        isNull,
      );
    });
  });
}

Track _local(
  String id, {
  String? uri,
  String? filePath,
  String title = 'Song',
  String artist = 'Artist',
  String album = 'Album',
  int? durationMs,
  String? contentFingerprint,
  String sourceType = 'windows_file',
  bool isAvailable = true,
}) => Track(
  id: id,
  sourceType: sourceType,
  sourceId: filePath ?? uri ?? 'file:///D:/Music/$id.mp3',
  uri: uri ?? 'file:///D:/Music/$id.mp3',
  filePath: filePath,
  title: title,
  artist: artist,
  album: album,
  durationMs: durationMs,
  contentFingerprint: contentFingerprint,
  isAvailable: isAvailable,
  syncState: 'local',
  updatedAt: DateTime(2026),
);

BackendTrack _remote({
  required String uri,
  String title = 'Song',
  String artist = 'Artist',
  String album = 'Album',
  int? durationMs,
  String? matchToken,
}) => BackendTrack(
  uri: uri,
  title: title,
  artist: artist,
  album: album,
  durationMs: durationMs,
  matchToken: matchToken,
);
