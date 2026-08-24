import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_music/app/providers.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/core/online_music/online_download_platform.dart';
import 'package:flutter_music/core/online_music/online_search_settings.dart';
import 'package:flutter_music/core/online_music/online_track.dart';
import 'package:flutter_music/core/online_music/online_track_downloader.dart';
import 'package:flutter_music/features/placeholders/settings_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('设置页展示并更新在线音乐下载目录', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final downloader = _FakeDownloader();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          onlineTrackDownloaderProvider.overrideWithValue(downloader),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('尚未设置；下载在线歌曲前需要先选择目录'), findsOneWidget);
    expect(find.text('显示搜索结果封面'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, '显示搜索结果封面'),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.text('显示搜索结果封面'));
    await tester.pumpAndSettle();
    expect(
      await database.readSetting(onlineSearchShowArtworkSettingKey),
      'false',
    );
    await tester.tap(find.widgetWithText(FilledButton, '选择'));
    await tester.pumpAndSettle();

    expect(find.text('内部存储/Music/Downloads'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '更改'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });
}

class _FakeDownloader implements OnlineTrackDownloader {
  OnlineDownloadDestination? _destination;

  @override
  bool get supported => true;

  @override
  Future<OnlineDownloadDestination?> chooseDestination() async =>
      _destination = const OnlineDownloadDestination(
        uri: 'content://downloads',
        label: '内部存储/Music/Downloads',
      );

  @override
  Future<OnlineDownloadDestination?> destination() async => _destination;

  @override
  Future<OnlineDownloadBatchResult> downloadAll(
    List<OnlineTrack> tracks, {
    void Function(OnlineDownloadProgress progress)? onProgress,
  }) => throw UnimplementedError();
}
