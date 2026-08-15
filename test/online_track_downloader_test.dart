import 'dart:typed_data';

import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/core/online_music/online_download_platform.dart';
import 'package:flutter_music/core/online_music/online_music_repository.dart';
import 'package:flutter_music/core/online_music/online_track.dart';
import 'package:flutter_music/core/online_music/online_track_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('批量下载逐首保存，失败项不会中断后续歌曲', () async {
    final settings = <String, String>{};
    final platform = _FakeDownloadPlatform(failingTrackId: 'failed');
    final savedTracks = <TracksCompanion>[];
    final downloader = DefaultOnlineTrackDownloader(
      repository: const _FakeRepository(),
      platform: platform,
      readSetting: (key) async => settings[key],
      writeSetting: (key, value) async => settings[key] = value,
      saveDownloadedTrack: (track) async => savedTracks.add(track),
    );

    final destination = await downloader.chooseDestination();
    final progress = <OnlineDownloadProgress>[];
    final result = await downloader.downloadAll(const [
      _track,
      OnlineTrack(
        provider: 'source',
        trackId: 'failed',
        title: '失败歌曲',
        artists: ['歌手'],
        album: '专辑',
        playable: true,
        capabilities: {'playback'},
      ),
    ], onProgress: progress.add);

    expect(destination?.label, '测试目录');
    expect(settings[onlineDownloadDirectorySettingKey], 'test://downloads');
    expect(result.downloaded, [_track]);
    expect(result.failures.single.track.trackId, 'failed');
    expect(savedTracks.single.id.value, 'online:source:track/1');
    expect(savedTracks.single.sourceType.value, 'windows_file');
    expect(platform.fileNames.single, '歌手_ - 标题_.flac');
    expect(progress.last.completed, 2);
  });

  test('下载文件名支持歌曲名在前和只有歌曲名', () async {
    for (final entry in <String, String>{
      'title_artist': '标题_ - 歌手_.flac',
      'title_only': '标题_.flac',
    }.entries) {
      final platform = _FakeDownloadPlatform();
      final downloader = DefaultOnlineTrackDownloader(
        repository: const _FakeRepository(),
        platform: platform,
        readSetting: (key) async => switch (key) {
          onlineDownloadDirectorySettingKey => 'test://downloads',
          onlineDownloadDirectoryLabelSettingKey => '测试目录',
          onlineDownloadFilenameFormatSettingKey => entry.key,
          _ => null,
        },
        writeSetting: (_, _) async {},
        saveDownloadedTrack: (_) async {},
      );

      final result = await downloader.downloadAll(const [_track]);

      expect(result.failures, isEmpty);
      expect(platform.fileNames.single, entry.value);
    }
  });

  test('无法内嵌时把封面和歌词保存到音频同目录', () async {
    final platform = _FakeDownloadPlatform();
    final downloader = DefaultOnlineTrackDownloader(
      repository: _FakeRepository(
        artwork: Uint8List.fromList([0xff, 0xd8, 0xff]),
        lyrics: '[00:01.00]歌词',
      ),
      platform: platform,
      readSetting: (key) async => switch (key) {
        onlineDownloadDirectorySettingKey => 'test://downloads',
        onlineDownloadDirectoryLabelSettingKey => '测试目录',
        onlineDownloadFilenameFormatSettingKey => 'title_only',
        _ => null,
      },
      writeSetting: (_, _) async {},
      saveDownloadedTrack: (_) async {},
    );

    final result = await downloader.downloadAll(const [
      OnlineTrack(
        provider: 'source',
        trackId: 'with-assets',
        title: '歌曲',
        artists: ['歌手'],
        album: '专辑',
        playable: true,
        capabilities: {'playback', 'artwork', 'lyrics'},
      ),
    ]);

    expect(result.failures, isEmpty);
    expect(platform.companionNames, ['歌曲.jpg', '歌曲.lrc']);
  });
}

const _track = OnlineTrack(
  provider: 'source',
  trackId: 'track/1',
  title: '标题?',
  artists: ['歌手*'],
  album: '专辑',
  playable: true,
  capabilities: {'playback'},
);

class _FakeRepository
    implements OnlineMusicSearchRepository, OnlineMusicDownloadRepository {
  const _FakeRepository({this.artwork, this.lyrics});

  final Uint8List? artwork;
  final String? lyrics;

  @override
  Future<OnlinePlaybackSource> prepareDownload(OnlineTrack track) =>
      preparePlayback(track);

  @override
  Future<OnlinePlaybackSource> preparePlayback(OnlineTrack track) async =>
      OnlinePlaybackSource(
        url: Uri.parse('https://example.test/${track.trackId}'),
        expiresAt: DateTime(2030),
        headers: const {'Authorization': 'Bearer test'},
        mimeType: 'audio/flac',
      );

  @override
  Future<Uint8List?> loadArtwork(OnlineTrack track) async => artwork;

  @override
  Future<String?> loadLyrics(OnlineTrack track) async => lyrics;

  @override
  Future<OnlineMusicSearchResult> search(String query, {String? cursor}) =>
      throw UnimplementedError();
}

class _FakeDownloadPlatform
    implements OnlineDownloadPlatform, OnlineDownloadCompanionPlatform {
  _FakeDownloadPlatform({this.failingTrackId});

  final String? failingTrackId;
  final fileNames = <String>[];
  final companionNames = <String>[];

  @override
  bool get supported => true;

  @override
  Future<OnlineDownloadDestination?> chooseDestination() async =>
      const OnlineDownloadDestination(uri: 'test://downloads', label: '测试目录');

  @override
  Future<DownloadedOnlineFile> save({
    required OnlineDownloadDestination destination,
    required OnlineTrack track,
    required OnlinePlaybackSource source,
    required String fileName,
  }) async {
    if (track.trackId == failingTrackId) throw StateError('failed');
    fileNames.add(fileName);
    return const DownloadedOnlineFile(
      uri: 'file:///downloads/song.flac',
      sourceType: 'windows_file',
      sourceId: r'C:\downloads\song.flac',
      filePath: r'C:\downloads\song.flac',
      bytes: 42,
    );
  }

  @override
  Future<void> saveCompanion({
    required OnlineDownloadDestination destination,
    required String fileName,
    required List<int> bytes,
    required String mimeType,
  }) async {
    companionNames.add(fileName);
  }
}
