import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_music/core/library/library_scanner_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Linux 桌面扫描递归收集音频、歌词并使用 Linux 来源类型', () async {
    final root = await Directory.systemTemp.createTemp(
      'flutter_music_linux_scan_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final album = await Directory(p.join(root.path, 'Album')).create();
    final audio = File(p.join(album.path, 'Track.WAV'));
    await audio.writeAsBytes(_emptyPcmWave);
    await File(
      p.setExtension(audio.path, '.lrc'),
    ).writeAsString('[00:01.00]Linux lyric');
    await File(p.join(album.path, 'cover.txt')).writeAsString('ignored');

    final result = await scanDesktopDirectory(root.path, isWindows: false);

    expect(result.sourceUri, p.normalize(root.absolute.path));
    expect(result.tracks, hasLength(1));
    final track = result.tracks.single;
    expect(track.sourceType, 'linux_file');
    expect(track.filePath, p.normalize(audio.absolute.path));
    expect(track.uri, Uri.file(p.normalize(audio.absolute.path)).toString());
    expect(track.title, 'Track');
    expect(track.lyrics, '[00:01.00]Linux lyric');
    expect(track.contentFingerprint, 'sha256:${sha256.convert(_emptyPcmWave)}');
  });
}

const _emptyPcmWave = <int>[
  0x52,
  0x49,
  0x46,
  0x46,
  0x24,
  0x00,
  0x00,
  0x00,
  0x57,
  0x41,
  0x56,
  0x45,
  0x66,
  0x6D,
  0x74,
  0x20,
  0x10,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x44,
  0xAC,
  0x00,
  0x00,
  0x88,
  0x58,
  0x01,
  0x00,
  0x02,
  0x00,
  0x10,
  0x00,
  0x64,
  0x61,
  0x74,
  0x61,
  0x00,
  0x00,
  0x00,
  0x00,
];
