import 'package:drift/native.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test(
    'deleting a Windows source keeps tracks from sibling directories',
    () async {
      const source = r'C:\Music';
      await database.upsertTracks([
        _track(id: 'inside', path: r'C:\Music\Album\inside.mp3'),
        _track(id: 'sibling', path: r'C:\Music-old\sibling.mp3'),
      ]);
      await database.saveScanSource(_source(id: 'music', uri: source));

      final scanSource = (await database.watchScanSources().first).single;
      await database.deleteScanSource(scanSource);

      expect((await database.allTracks()).map((track) => track.id), [
        'sibling',
      ]);
    },
  );

  test('rescanning a Windows source does not prune a sibling source', () async {
    const source = r'C:\Music';
    await database.upsertTracks([
      _track(id: 'stale', path: r'C:\Music\stale.mp3'),
      _track(id: 'sibling', path: r'C:\Music-old\sibling.mp3'),
    ]);
    await database.saveScanSource(_source(id: 'music', uri: source));
    final scanSource = (await database.watchScanSources().first).single;

    await database.replaceScanSourceTracks(scanSource, const []);

    expect((await database.allTracks()).map((track) => track.id), ['sibling']);
  });

  test(
    'source paths containing SQL pattern characters are matched literally',
    () async {
      const source = r'C:\100%_Music';
      await database.upsertTracks([
        _track(id: 'inside', path: r'C:\100%_Music\inside.mp3'),
        _track(id: 'similar', path: r'C:\100 HitsMusic\similar.mp3'),
      ]);
      await database.saveScanSource(_source(id: 'music', uri: source));

      await database.deleteScanSource(
        (await database.watchScanSources().first).single,
      );

      expect((await database.allTracks()).map((track) => track.id), [
        'similar',
      ]);
    },
  );

  test('rescanning a Linux source prunes only that path boundary', () async {
    const source = '/home/user/Music';
    await database.upsertTracks([
      _track(
        id: 'linux-stale',
        path: '/home/user/Music/stale.flac',
        sourceType: 'linux_file',
        windowsUri: false,
      ),
      _track(
        id: 'linux-sibling',
        path: '/home/user/Music-old/sibling.flac',
        sourceType: 'linux_file',
        windowsUri: false,
      ),
    ]);
    await database.saveScanSource(
      _source(id: 'linux-music', uri: source, platform: 'linux_file'),
    );

    final scanSource = (await database.watchScanSources().first).single;
    await database.replaceScanSourceTracks(scanSource, const []);

    expect((await database.allTracks()).map((track) => track.id), [
      'linux-sibling',
    ]);
  });
}

TracksCompanion _track({
  required String id,
  required String path,
  String sourceType = 'windows_file',
  bool windowsUri = true,
}) {
  return TracksCompanion.insert(
    id: id,
    sourceType: sourceType,
    sourceId: path,
    uri: Uri.file(path, windows: windowsUri).toString(),
    title: id,
    updatedAt: DateTime(2026),
  );
}

ScanSourcesCompanion _source({
  required String id,
  required String uri,
  String platform = 'windows_file',
}) {
  return ScanSourcesCompanion.insert(
    id: id,
    platform: platform,
    uri: uri,
    label: id,
  );
}
