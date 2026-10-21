import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_music/core/update/app_version.dart';
import 'package:flutter_music/core/update/update_manifest.dart';
import 'package:flutter_music/core/update/update_service.dart';
import 'package:flutter_music/core/update/update_service_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final Uri _manifestUri = Uri.parse(
  'https://github.com/zonwe/SimulGroove-Music/releases/latest/download/latest.json',
);
final Uri _assetUri = Uri.parse(
  'https://github.com/zonwe/SimulGroove-Music/releases/download/v1.1.1/Setup-1.1.1.exe',
);

Map<String, Object?> _manifest({
  String version = '1.1.1',
  int buildNumber = 5,
  String url =
      'https://github.com/zonwe/SimulGroove-Music/releases/download/v1.1.1/Setup-1.1.1.exe',
  int size = 24,
  String? sha256,
}) => {
  'schemaVersion': 1,
  'channel': 'stable',
  'version': version,
  'buildNumber': buildNumber,
  'publishedAt': '2026-10-21T00:00:00Z',
  'notes': 'test release',
  'assets': {
    'windows-x64': {
      'url': url,
      'size': size,
      'sha256': sha256 ?? 'a' * 64,
      'kind': 'installer',
    },
  },
};

DesktopAppUpdateService _service(
  Directory temp, {
  required http.Client client,
  String currentVersion = '1.1.0+4',
}) => DesktopAppUpdateService(
  client: client,
  manifestUri: _manifestUri,
  readInstalledVersion: () async => currentVersion,
  temporaryDirectory: () async => temp,
  executablePath: '${temp.path}/simul_groove_player.exe',
  windowsOverride: true,
  platformKeyOverride: 'windows-x64',
  installedOverride: true,
);

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('simulgroove-update-test-');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('returns an available update with the selected Windows asset', () async {
    final client = MockClient((request) async {
      expect(request.url, _manifestUri);
      return http.Response(jsonEncode(_manifest()), 200);
    });
    final service = _service(temp, client: client);

    final result = await service.checkForUpdates();

    expect(result, isA<UpdateAvailable>());
    final available = result as UpdateAvailable;
    expect(available.current, AppVersion.parse('1.1.0+4'));
    expect(available.release.version, AppVersion.parse('1.1.1+5'));
    expect(available.asset.uri, _assetUri);
    expect(available.asset.kind, UpdateAssetKind.installer);
  });

  test('reports up to date when the manifest version is not newer', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(_manifest(version: '1.1.0', buildNumber: 4)),
        200,
      ),
    );
    final service = _service(temp, client: client);

    final result = await service.checkForUpdates();

    expect(result, isA<UpdateUpToDate>());
  });

  test('rejects assets from an untrusted host', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(_manifest(url: 'https://evil.example/Setup-1.1.1.exe')),
        200,
      ),
    );
    final service = _service(temp, client: client);

    expect(
      service.checkForUpdates(),
      throwsA(
        isA<UpdateException>().having(
          (error) => error.code,
          'code',
          'update_untrusted_host',
        ),
      ),
    );
  });

  test('surfaces a missing manifest as a readable error', () async {
    final client = MockClient(
      (request) async => http.Response('not found', 404),
    );
    final service = _service(temp, client: client);

    expect(
      service.checkForUpdates(),
      throwsA(
        isA<UpdateException>().having(
          (error) => error.code,
          'code',
          'update_manifest_http_404',
        ),
      ),
    );
  });

  test('downloads, verifies and reports progress', () async {
    final bytes = utf8.encode('fake windows installer payload');
    final digest = sha256.convert(bytes).toString();
    final client = MockClient((request) async {
      if (request.url == _manifestUri) {
        return http.Response(
          jsonEncode(_manifest(size: bytes.length, sha256: digest)),
          200,
        );
      }
      expect(request.url, _assetUri);
      return http.Response.bytes(bytes, 200);
    });
    final service = _service(temp, client: client);
    final available = await service.checkForUpdates() as UpdateAvailable;

    var received = 0;
    int? total;
    final path = await service.downloadUpdate(
      available.asset,
      onProgress: (current, expected) {
        received = current;
        total = expected;
      },
    );

    expect(received, bytes.length);
    expect(total, bytes.length);
    final downloaded = File(path);
    expect(downloaded.existsSync(), isTrue);
    expect(downloaded.readAsBytesSync(), bytes);
    expect(path.endsWith('Setup-1.1.1.exe'), isTrue);
  });

  test('deletes the partial download when the checksum mismatches', () async {
    final bytes = utf8.encode('fake windows installer payload');
    final client = MockClient((request) async {
      if (request.url == _manifestUri) {
        return http.Response(
          jsonEncode(_manifest(size: bytes.length, sha256: 'b' * 64)),
          200,
        );
      }
      return http.Response.bytes(bytes, 200);
    });
    final service = _service(temp, client: client);
    final available = await service.checkForUpdates() as UpdateAvailable;

    await expectLater(
      service.downloadUpdate(available.asset),
      throwsA(
        isA<UpdateException>().having(
          (error) => error.code,
          'code',
          'update_checksum_mismatch',
        ),
      ),
    );

    final updateDirectory = Directory(
      '${temp.path}${Platform.pathSeparator}SimulGrooveMusic'
      '${Platform.pathSeparator}updates',
    );
    final leftovers = updateDirectory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.part'))
        .toList();
    expect(leftovers, isEmpty);
  });

  test('refuses a non-installer asset on Windows', () async {
    final asset = UpdateAsset(
      uri: _assetUri,
      size: 16,
      sha256:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      kind: UpdateAssetKind.apk,
    );
    final service = _service(
      temp,
      client: MockClient((request) async => http.Response('', 500)),
    );

    await expectLater(
      service.downloadUpdate(asset),
      throwsA(
        isA<UpdateException>().having(
          (error) => error.code,
          'code',
          'update_asset_kind',
        ),
      ),
    );
  });
}
