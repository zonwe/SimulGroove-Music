import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_music/app/providers.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/core/library/library_scanner.dart';
import 'package:flutter_music/core/library/scanned_track.dart';
import 'package:flutter_music/core/library/scan_fingerprint.dart';
import 'package:flutter_music/core/notifications/scan_notification_service.dart';
import 'package:flutter_music/core/notifications/scan_notification_service_stub.dart';
import 'package:flutter_music/features/library/library_scan_settings_section.dart';

class FakeScanNotificationService implements ScanNotificationService {
  final List<String> events = [];

  @override
  Future<void> initialize() async {
    events.add('initialize');
  }

  @override
  Future<void> notifyScanStarted({
    required String sourceLabel,
    bool isRescan = false,
  }) async {
    events.add('started:$sourceLabel:$isRescan');
  }

  @override
  Future<void> notifyScanCompleted({
    required String sourceLabel,
    required int trackCount,
    bool isRescan = false,
  }) async {
    events.add('completed:$sourceLabel:$trackCount:$isRescan');
  }

  @override
  Future<void> notifyScanFailed({
    required String sourceLabel,
    required String errorMessage,
  }) async {
    events.add('failed:$sourceLabel:$errorMessage');
  }

  @override
  Future<void> cancelScanNotification() async {
    events.add('cancelled');
  }
}

class FakeLibraryScanner implements LibraryScanner {
  FakeLibraryScanner({
    this.scanResult,
    this.shouldThrow = false,
    this.supported = true,
    this.fullDevice = true,
  });

  final ScanResult? scanResult;
  final bool shouldThrow;
  final bool supported;
  final bool fullDevice;

  @override
  String get actionLabel => '添加音乐文件夹';

  @override
  bool get isSupported => supported;

  @override
  bool get supportsFullDeviceScan => fullDevice;

  @override
  Future<ScanResult?> scan() async {
    if (shouldThrow) throw Exception('扫描目录读取失败');
    return scanResult;
  }

  @override
  Future<ScanResult?> scanFullDevice() async {
    if (shouldThrow) throw Exception('全盘扫描失败');
    return scanResult;
  }

  @override
  Future<ScanResult?> rescanSource({
    required String sourceUri,
    required String platform,
    required String sourceLabel,
    List<ScanFingerprint> fingerprintCache = const [],
  }) async {
    if (shouldThrow) throw Exception('重新扫描失败');
    return scanResult;
  }
}

void main() {
  group('ScanNotificationService Stub', () {
    test('stub methods execute gracefully without errors', () async {
      final stub = createScanNotificationService();
      await stub.initialize();
      await stub.notifyScanStarted(sourceLabel: '测试目录');
      await stub.notifyScanCompleted(sourceLabel: '测试目录', trackCount: 10);
      await stub.notifyScanFailed(sourceLabel: '测试目录', errorMessage: '出错了');
      await stub.cancelScanNotification();
    });
  });

  group('Scan Notification Provider & UI', () {
    testWidgets('renders scan notification switch and toggles setting', (
      tester,
    ) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final fakeNotifier = FakeScanNotificationService();
      final scanner = FakeLibraryScanner(
        scanResult: const ScanResult(
          tracks: [],
          sourceUri: 'D:/Music',
          sourceLabel: 'Music',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            scannerProvider.overrideWithValue(scanner),
            scanNotificationServiceProvider.overrideWithValue(fakeNotifier),
          ],
          child: const MaterialApp(
            home: Scaffold(body: LibraryScanSettingsSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('扫描通知'), findsOneWidget);
      expect(find.text('音乐库扫描进行与完成时发送系统通知'), findsOneWidget);

      final switchFinder = find.widgetWithText(SwitchListTile, '扫描通知');
      expect(switchFinder, findsOneWidget);

      final switchWidget = tester.widget<SwitchListTile>(switchFinder);
      expect(switchWidget.value, isTrue);

      // Toggle switch to false
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      final updatedSetting = await database.readSetting(
        scanNotificationEnabledSettingKey,
      );
      expect(updatedSetting, equals('false'));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await database.close();
    });

    testWidgets('triggers notification on successful scan', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final fakeNotifier = FakeScanNotificationService();
      final scanner = FakeLibraryScanner(
        scanResult: const ScanResult(
          tracks: [
            ScannedTrack(
              id: 'track-1',
              sourceType: 'windows_file',
              sourceId: 'D:/Music/test.mp3',
              uri: 'file:///D:/Music/test.mp3',
              filePath: 'D:/Music/test.mp3',
              title: '测试音乐',
              artist: '测试艺术家',
              album: '测试专辑',
            ),
          ],
          sourceUri: 'D:/Music',
          sourceLabel: 'Music',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            scannerProvider.overrideWithValue(scanner),
            scanNotificationServiceProvider.overrideWithValue(fakeNotifier),
          ],
          child: const MaterialApp(
            home: Scaffold(body: LibraryScanSettingsSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger scan
      await tester.tap(find.text('添加音乐文件夹'));
      await tester.pumpAndSettle();

      expect(fakeNotifier.events, contains('started:音乐文件夹:false'));
      expect(fakeNotifier.events, contains('completed:Music:1:false'));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await database.close();
    });

    testWidgets('triggers notification on failed scan', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final fakeNotifier = FakeScanNotificationService();
      final scanner = FakeLibraryScanner(shouldThrow: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            scannerProvider.overrideWithValue(scanner),
            scanNotificationServiceProvider.overrideWithValue(fakeNotifier),
          ],
          child: const MaterialApp(
            home: Scaffold(body: LibraryScanSettingsSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger scan
      await tester.tap(find.text('添加音乐文件夹'));
      await tester.pumpAndSettle();

      expect(fakeNotifier.events, contains('started:音乐文件夹:false'));
      expect(
        fakeNotifier.events.any((e) => e.startsWith('failed:音乐文件夹:')),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await database.close();
    });

    testWidgets('does not send notification when disabled by user', (
      tester,
    ) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final fakeNotifier = FakeScanNotificationService();
      await database.setSetting(scanNotificationEnabledSettingKey, 'false');

      final scanner = FakeLibraryScanner(
        scanResult: const ScanResult(
          tracks: [],
          sourceUri: 'D:/Music',
          sourceLabel: 'Music',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            scannerProvider.overrideWithValue(scanner),
            scanNotificationServiceProvider.overrideWithValue(fakeNotifier),
          ],
          child: const MaterialApp(
            home: Scaffold(body: LibraryScanSettingsSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('添加音乐文件夹'));
      await tester.pumpAndSettle();

      expect(fakeNotifier.events, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await database.close();
    });
  });
}
