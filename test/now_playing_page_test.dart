import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_music/core/player/now_playing_layout.dart';
import 'package:flutter_music/core/lyrics/lrc_parser.dart';
import 'package:flutter_music/features/player/lyrics_panel.dart';
import 'package:flutter_music/features/player/now_playing_page.dart';
import 'package:flutter_music/features/player/track_info_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android、Windows 和 Linux 显示正在播放页歌曲信息按钮', () {
    expect(
      shouldShowNowPlayingTrackInfoButton(TargetPlatform.android, isWeb: false),
      isTrue,
    );
    expect(
      shouldShowNowPlayingTrackInfoButton(TargetPlatform.windows, isWeb: false),
      isTrue,
    );
    expect(
      shouldShowNowPlayingTrackInfoButton(TargetPlatform.linux, isWeb: false),
      isTrue,
    );
    expect(
      shouldShowNowPlayingTrackInfoButton(TargetPlatform.windows, isWeb: true),
      isFalse,
    );
  });

  test('双栏布局在 Windows 和 Linux 宽窗口启用', () {
    expect(
      shouldUseSplitNowPlayingLayout(
        layout: NowPlayingLayout.split,
        platform: TargetPlatform.linux,
        isWeb: false,
        availableWidth: 1200,
      ),
      isTrue,
    );
    expect(
      shouldUseSplitNowPlayingLayout(
        layout: NowPlayingLayout.split,
        platform: TargetPlatform.windows,
        isWeb: false,
        availableWidth: 1200,
      ),
      isTrue,
    );
    expect(
      shouldUseSplitNowPlayingLayout(
        layout: NowPlayingLayout.split,
        platform: TargetPlatform.windows,
        isWeb: false,
        availableWidth: 899,
      ),
      isFalse,
    );
    expect(
      shouldUseSplitNowPlayingLayout(
        layout: NowPlayingLayout.classic,
        platform: TargetPlatform.windows,
        isWeb: false,
        availableWidth: 1200,
      ),
      isFalse,
    );
  });

  test('末句歌词贴底并忽略其后的空结束时间标记', () {
    final lines = parseLrc(
      '[00:01.00]第一句\n[00:02.00]最后一句\n[00:03.00]\n[00:04.00]',
    );

    expect(lyricsScrollTargetIndex(lines, 0), 0);
    expect(lyricsScrollAlignment(lines, 0), 0.5);
    expect(lyricsScrollTargetIndex(lines, 1), 1);
    expect(lyricsScrollAlignment(lines, 1), 1);
    expect(lyricsScrollTargetIndex(lines, 2), 1);
    expect(lyricsScrollTargetIndex(lines, 3), 1);
  });

  testWidgets('多个歌手会拆分为可独立点击的链接', (tester) async {
    final openedArtists = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NowPlayingArtistLinks(
            artistTag: '鸣潮先锋电台/Casey Lee Williams',
            album: 'Running For Your Life',
            onArtistTap: openedArtists.add,
          ),
        ),
      ),
    );

    expect(find.byTooltip('查看歌手：鸣潮先锋电台'), findsOneWidget);
    expect(find.byTooltip('查看歌手：Casey Lee Williams'), findsOneWidget);
    await tester.tap(find.text('Casey Lee Williams'));
    await tester.pump();

    expect(openedArtists, ['Casey Lee Williams']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('双栏布局在深色大字体下同时展示封面和歌词', (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const item = MediaItem(
      id: 'split-track',
      title: 'Split Song',
      extras: {'lyrics': '[00:00.00]第一句歌词\n[00:05.00]第二句歌词'},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(24),
              child: NowPlayingSplitArtworkLyrics(
                item: item,
                positionStream: Stream.empty(),
                initialPosition: Duration.zero,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey(('split-cover', 'split-track'))),
      findsOneWidget,
    );
    expect(find.text('第一句歌词'), findsOneWidget);
    expect(find.text('第二句歌词'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('双栏布局在较矮窗口中不会溢出', (tester) async {
    tester.view.physicalSize = const Size(1200, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const item = MediaItem(
      id: 'short-split-track',
      title: 'Short Window Song',
      extras: {'lyrics': '[00:00.00]歌词'},
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: NowPlayingSplitArtworkLyrics(
              item: item,
              positionStream: Stream.empty(),
              initialPosition: Duration.zero,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('歌曲信息按钮可打开详情面板', (tester) async {
    const item = MediaItem(
      id: 'track-1',
      title: 'Test Song',
      artist: 'Test Artist',
      album: 'Test Album',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: TrackInfoButton(item: item)),
        ),
      ),
    );

    expect(find.byTooltip('歌曲信息'), findsOneWidget);
    await tester.tap(find.byTooltip('歌曲信息'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, '歌手'), findsOneWidget);
    expect(find.text('Test Artist'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '专辑'), findsOneWidget);
    expect(find.text('Test Album'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
