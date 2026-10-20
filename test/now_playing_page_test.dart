import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_music/core/player/now_playing_layout.dart';
import 'package:flutter_music/core/lyrics/lrc_parser.dart';
import 'package:flutter_music/features/player/lyrics_panel.dart';
import 'package:flutter_music/features/player/now_playing_artwork_lyrics_pager.dart';
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

  testWidgets('切到歌词视图时立即定位到当前播放位置', (tester) async {
    // 视口外的歌词行必须真实构建出来，否则 GlobalKey 拿不到 context，
    // ensureVisible 会静默跳过，歌词停在顶部且不再跟随。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricsPanel(
            lyrics: _manyLyrics(60),
            positionStream: const Stream<Duration>.empty(),
            initialPosition: const Duration(seconds: 40),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byType(LyricsPanel));
    final current = tester.getRect(find.text('第40句'));
    expect(panel.contains(current.center), isTrue);
    expect((current.center.dy - panel.center.dy).abs(), lessThan(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('播放推进时歌词跟随滚动到新的当前行', (tester) async {
    final positions = StreamController<Duration>.broadcast();
    addTearDown(positions.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricsPanel(
            lyrics: _manyLyrics(60),
            positionStream: positions.stream,
            initialPosition: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pump();
    final panel = tester.getRect(find.byType(LyricsPanel));

    positions.add(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(panel.contains(tester.getRect(find.text('第30句')).center), isTrue);

    positions.add(const Duration(seconds: 45));
    await tester.pumpAndSettle();
    expect(panel.contains(tester.getRect(find.text('第45句')).center), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('左右滑动在封面和歌词之间切换', (tester) async {
    await tester.pumpWidget(_pagerApp());
    await tester.pump();

    expect(find.byKey(const ValueKey('cover')), findsOneWidget);
    expect(find.text('第一句歌词'), findsNothing);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('第一句歌词'), findsOneWidget);
    expect(find.byKey(const ValueKey('cover')), findsNothing);

    await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cover')), findsOneWidget);
    expect(find.text('第一句歌词'), findsNothing);
  });

  testWidgets('关闭歌词点击定位后点按歌词页切回封面', (tester) async {
    await tester.pumpWidget(_pagerApp());
    await tester.tap(find.byKey(const ValueKey('now-playing-cover-page')));
    await tester.pumpAndSettle();
    expect(find.text('第二句歌词'), findsOneWidget);

    await tester.tap(find.text('第二句歌词'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cover')), findsOneWidget);
    expect(find.text('第二句歌词'), findsNothing);
  });

  testWidgets('开启歌词点击定位时点按歌词行只定位不切页', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(_pagerApp(onSeek: seeks.add));
    await tester.tap(find.byKey(const ValueKey('now-playing-cover-page')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('第二句歌词'));
    await tester.pumpAndSettle();
    expect(seeks, [const Duration(seconds: 5)]);
    expect(find.text('第二句歌词'), findsOneWidget);
    expect(find.byKey(const ValueKey('cover')), findsNothing);
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

/// 生成 [count] 句、每句间隔 1 秒的同步歌词，用于验证滚动定位。
String _manyLyrics(int count) => List<String>.generate(
  count,
  (index) => '[00:${index.toString().padLeft(2, '0')}.00]第$index句',
).join('\n');

/// 经典播放布局：封面与歌词分页。
Widget _pagerApp({ValueChanged<Duration>? onSeek}) => MaterialApp(
  home: Scaffold(
    body: NowPlayingArtworkLyricsPager(
      item: const MediaItem(
        id: 'pager-track',
        title: 'Pager Song',
        extras: {'lyrics': '[00:00.00]第一句歌词\n[00:05.00]第二句歌词'},
      ),
      positionStream: const Stream<Duration>.empty(),
      initialPosition: Duration.zero,
      onSeek: onSeek,
    ),
  ),
);
