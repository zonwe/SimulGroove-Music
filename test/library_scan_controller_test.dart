import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_music/app/providers.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/core/library/library_scan_controller.dart';
import 'package:flutter_music/core/library/scanned_track.dart';
import 'package:flutter_music/features/library/library_scan_settings_section.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scan_notification_service_test.dart'
    show FakeLibraryScanner, FakeScanNotificationService;

void main() {
  testWidgets(
    'scan survives page disposal and prevents concurrent rescan and deletion',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final scanner = _DelayedScanner();
      final notifications = FakeScanNotificationService();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          scannerProvider.overrideWithValue(scanner),
          scanNotificationServiceProvider.overrideWithValue(notifications),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      await db.saveScanSource(
        ScanSourcesCompanion.insert(
          id: 'existing',
          platform: 'test',
          uri: 'test://existing',
          label: 'existing',
        ),
      );
      final source = (await db.select(db.scanSources).get()).single;
      final controller = container.read(libraryScanControllerProvider);
      Widget page(bool visible) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: visible
                ? const LibraryScanSettingsSection()
                : const Text('音乐库'),
          ),
        ),
      );
      await tester.pumpWidget(page(true));
      final pending = controller.scan();
      await tester.pump();
      expect(controller.busy, isTrue);
      await controller.rescanAll();
      await controller.deleteSource(source);
      await tester.pumpWidget(page(false));
      scanner.result.complete(_result);
      await tester.pumpAndSettle();
      await pending;
      expect(controller.busy, isFalse);
      expect((await db.allTracks()).single.id, 'track');
      expect(await db.select(db.scanSources).get(), hasLength(2));
      expect(notifications.events, contains('completed:Music:1:false'));
      await tester.pumpWidget(page(true));
      await tester.pumpAndSettle();
      expect(find.text('已导入 1 首歌曲'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'notification errors cannot prevent a scan from being committed',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final controller = LibraryScanController(
        db,
        FakeLibraryScanner(scanResult: _result),
        _BrokenNotifications(),
      );
      addTearDown(() async {
        controller.dispose();
        await db.close();
      });
      await controller.scan();
      expect(controller.hasError, isFalse);
      expect(controller.busy, isFalse);
      expect((await db.allTracks()).single.id, 'track');
    },
  );

  test(
    'scan writes artwork to its own table and a cover-less rescan clears it',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final cover = Uint8List.fromList([0x0A, 0x0B, 0x0C]);
      final controller = LibraryScanController(
        db,
        FakeLibraryScanner(scanResult: _scanResultWithArtwork(cover)),
        FakeScanNotificationService(),
      );
      addTearDown(() async {
        controller.dispose();
        await db.close();
      });

      await controller.scan();
      expect(await db.trackArtwork('track'), cover);

      // 文件元数据里没有封面时，重扫必须清掉上一版的图，而不是留下旧封面。
      final secondController = LibraryScanController(
        db,
        FakeLibraryScanner(scanResult: _scanResultWithArtwork(null)),
        FakeScanNotificationService(),
      );
      addTearDown(secondController.dispose);
      await secondController.scan();

      expect(await db.trackArtwork('track'), isNull);
      expect((await db.allTracks()).single.id, 'track');
    },
  );
}

ScanResult _scanResultWithArtwork(Uint8List? artwork) => ScanResult(
  tracks: [
    ScannedTrack(
      id: 'track',
      sourceType: 'test',
      sourceId: 'track',
      uri: 'test://track',
      title: 'track',
      artist: '',
      album: '',
      artwork: artwork,
    ),
  ],
  sourceUri: 'test://music',
  sourceLabel: 'Music',
);

class _DelayedScanner extends FakeLibraryScanner {
  final result = Completer<ScanResult?>();
  @override
  Future<ScanResult?> scan() => result.future;
}

class _BrokenNotifications extends FakeScanNotificationService {
  @override
  Future<void> notifyScanStarted({
    required String sourceLabel,
    bool isRescan = false,
  }) async => throw StateError('notifications unavailable');
}

const _result = ScanResult(
  tracks: [
    ScannedTrack(
      id: 'track',
      sourceType: 'test',
      sourceId: 'track',
      uri: 'test://track',
      title: 'track',
      artist: '',
      album: '',
    ),
  ],
  sourceUri: 'test://music',
  sourceLabel: 'Music',
);
