import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_music/core/update/app_version.dart';
import 'package:flutter_music/core/update/update_manifest.dart';
import 'package:flutter_music/core/update/update_settings.dart';

Map<String, Object?> _manifest({
  String url =
      'https://github.com/zonwe/SimulGroove-Music/releases/download/v1.1.0/SimulGrooveMusic-Setup-1.1.0.exe',
  String sha256 =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  String kind = 'installer',
  int size = 24000000,
}) => {
  'schemaVersion': 1,
  'channel': 'stable',
  'version': '1.1.0',
  'buildNumber': 4,
  'publishedAt': '2026-10-21T00:00:00Z',
  'notes': '- 新增应用内更新\n- 提供 Windows 安装器',
  'assets': {
    'windows-x64': {'url': url, 'size': size, 'sha256': sha256, 'kind': kind},
  },
};

void main() {
  group('AppVersion', () {
    test('parses version and build number', () {
      final version = AppVersion.parse('1.2.3+4');
      expect(version.versionText, '1.2.3');
      expect(version.buildNumber, 4);
      expect(version.canonical, '1.2.3+4');
      expect(version.display, '1.2.3（构建 4）');
    });

    test('compares semantic segments before build number', () {
      expect(
        AppVersion.parse('1.2.1+1').compareTo(AppVersion.parse('1.2.0+9')),
        greaterThan(0),
      );
      expect(
        AppVersion.parse('1.2.0+9').compareTo(AppVersion.parse('1.2.0+10')),
        lessThan(0),
      );
      expect(AppVersion.parse('2.0').compareTo(AppVersion.parse('2.0.0')), 0);
      expect(AppVersion.parse('2.0'), AppVersion.parse('2.0.0'));
    });

    test('rejects malformed versions', () {
      expect(() => AppVersion.parse('1.2.x'), throwsFormatException);
      expect(() => AppVersion.parse('1.2.3+'), throwsFormatException);
      expect(AppVersion.tryParse('dev'), isNull);
    });

    test('prefers an embedded build number from Android versionName', () {
      // Android 的 buildNumber 是 ABI 偏移后的 versionCode（arm64 为 2004），
      // Gradle 把真实构建号写进 versionName，解析时应优先使用它。
      expect(
        AppVersion.fromPackageInfoVersion('1.1.0+4', buildNumber: '2004'),
        AppVersion.parse('1.1.0+4'),
      );
      expect(
        AppVersion.fromPackageInfoVersion('1.1.0', buildNumber: '4'),
        AppVersion.parse('1.1.0+4'),
      );
    });
  });

  group('parseUpdateManifest', () {
    test('parses a valid Windows installer manifest', () {
      final manifest = parseUpdateManifest(_manifest());
      expect(manifest.channel, 'stable');
      expect(manifest.release.version, AppVersion.parse('1.1.0+4'));
      expect(manifest.release.notes, contains('应用内更新'));
      expect(manifest.release.publishedAt.isUtc, isTrue);

      final asset = manifest.release.assetFor('windows-x64');
      expect(asset, isNotNull);
      expect(asset!.kind, UpdateAssetKind.installer);
      expect(asset.size, 24000000);
      expect(asset.sha256, hasLength(64));
      expect(asset.suggestedFileName, 'SimulGrooveMusic-Setup-1.1.0.exe');
      expect(manifest.release.assetFor('linux-x64'), isNull);
    });

    test('accepts Android APK assets including underscore ABI keys', () {
      final json = _manifest();
      final assets = json['assets']! as Map<String, Object?>;
      assets['android-x86_64'] = {
        'url':
            'https://github.com/zonwe/SimulGroove-Music/releases/download/'
            'v1.1.0/SimulGroove-Music-v1.1.0-android-x86_64.apk',
        'size': 25000000,
        'sha256':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'kind': 'apk',
      };

      final manifest = parseUpdateManifest(json);

      expect(
        manifest.release.assetFor('android-x86_64')?.kind,
        UpdateAssetKind.apk,
      );
    });

    test('rejects unsupported schema versions', () {
      final json = _manifest()..['schemaVersion'] = 2;
      expect(() => parseUpdateManifest(json), throwsFormatException);
    });

    test('rejects insecure asset URLs and invalid digests', () {
      expect(
        () =>
            parseUpdateManifest(_manifest(url: 'http://example.com/setup.exe')),
        throwsFormatException,
      );
      expect(
        () => parseUpdateManifest(_manifest(sha256: 'not-a-sha')),
        throwsFormatException,
      );
      expect(
        () => parseUpdateManifest(_manifest(size: 0)),
        throwsFormatException,
      );
    });

    test('rejects unknown asset kinds', () {
      expect(
        () => parseUpdateManifest(_manifest(kind: 'msi')),
        throwsFormatException,
      );
    });

    test('requires a matching build number when version embeds one', () {
      final json = _manifest()
        ..['version'] = '1.1.0+9'
        ..['buildNumber'] = 4;
      expect(() => parseUpdateManifest(json), throwsFormatException);
    });

    test('limits oversized release notes', () {
      final json = _manifest()..['notes'] = 'a' * (maxUpdateNotesLength + 1);
      expect(() => parseUpdateManifest(json), throwsFormatException);
    });
  });

  group('update settings', () {
    test('auto check defaults to enabled and can be turned off', () {
      expect(updateAutoCheckFromSettings(const {}), isTrue);
      expect(
        updateAutoCheckFromSettings(const {updateAutoCheckSettingKey: 'false'}),
        isFalse,
      );
    });

    test('auto download defaults to off and requires explicit opt-in', () {
      expect(updateAutoDownloadFromSettings(const {}), isFalse);
      expect(
        updateAutoDownloadFromSettings(const {
          updateAutoDownloadSettingKey: 'false',
        }),
        isFalse,
      );
      expect(
        updateAutoDownloadFromSettings(const {
          updateAutoDownloadSettingKey: 'true',
        }),
        isTrue,
      );
    });

    test('startup checks are throttled to at most once per day', () {
      final now = DateTime(2026, 10, 21, 12);
      expect(
        shouldAutoCheckUpdates(enabled: true, lastCheckedAt: null, now: now),
        isTrue,
      );
      expect(
        shouldAutoCheckUpdates(
          enabled: true,
          lastCheckedAt: now.subtract(const Duration(hours: 23)),
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldAutoCheckUpdates(
          enabled: true,
          lastCheckedAt: now.subtract(const Duration(hours: 25)),
          now: now,
        ),
        isTrue,
      );
      expect(
        shouldAutoCheckUpdates(enabled: false, lastCheckedAt: null, now: now),
        isFalse,
      );
    });

    test('auto download requires opt-in, an installer and an update', () {
      expect(
        shouldAutoDownloadUpdate(
          autoDownloadEnabled: true,
          installed: true,
          updateAvailable: true,
        ),
        isTrue,
      );
      expect(
        shouldAutoDownloadUpdate(
          autoDownloadEnabled: false,
          installed: true,
          updateAvailable: true,
        ),
        isFalse,
      );
      // Windows 解压版没有卸载器，只能在对话框里引导手动安装。
      expect(
        shouldAutoDownloadUpdate(
          autoDownloadEnabled: true,
          installed: false,
          updateAvailable: true,
        ),
        isFalse,
      );
      expect(
        shouldAutoDownloadUpdate(
          autoDownloadEnabled: true,
          installed: true,
          updateAvailable: false,
        ),
        isFalse,
      );
    });
  });
}
