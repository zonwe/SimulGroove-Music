import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_music/app/providers.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/core/player/lyrics_settings.dart';
import 'package:flutter_music/features/player/lyrics_panel.dart';
import 'package:flutter_music/features/settings/lyrics_settings_section.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('歌词点击定位默认开启，确认默认关闭', () {
    expect(lyricsTapToSeekEnabledFromSettings(const {}), isTrue);
    expect(lyricsTapToSeekConfirmFromSettings(const {}), isFalse);
    expect(
      lyricsTapToSeekEnabledFromSettings(const {
        lyricsTapToSeekSettingKey: 'false',
      }),
      isFalse,
    );
    expect(
      lyricsTapToSeekConfirmFromSettings(const {
        lyricsTapToSeekConfirmSettingKey: 'true',
      }),
      isTrue,
    );
  });

  test('歌词时间格式化为分:秒', () {
    expect(formatLyricSeekTime(const Duration(seconds: 65)), '1:05');
    expect(formatLyricSeekTime(Duration.zero), '0:00');
  });

  test('二次点按确认判定：同一行再次点按才算确认', () {
    expect(
      lyricsTapNeedsConfirmation(
        confirmSeek: true,
        pendingIndex: null,
        tappedIndex: 2,
      ),
      isTrue,
    );
    expect(
      lyricsTapNeedsConfirmation(
        confirmSeek: true,
        pendingIndex: 2,
        tappedIndex: 2,
      ),
      isFalse,
    );
    expect(
      lyricsTapNeedsConfirmation(
        confirmSeek: true,
        pendingIndex: 2,
        tappedIndex: 3,
      ),
      isTrue,
    );
    expect(
      lyricsTapNeedsConfirmation(
        confirmSeek: false,
        pendingIndex: 2,
        tappedIndex: 2,
      ),
      isFalse,
    );
  });

  testWidgets('点击歌词会回调该行开始时间', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricsPanel(
            lyrics: '[00:00.00]第一句\n[00:05.00]第二句',
            positionStream: const Stream<Duration>.empty(),
            initialPosition: Duration.zero,
            onSeek: seeks.add,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('第二句'));
    await tester.pump();

    expect(seeks, [const Duration(seconds: 5)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击歌词不会触发外层的封面/歌词切换', (tester) async {
    var toggles = 0;
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => toggles++,
            child: LyricsPanel(
              lyrics: '[00:00.00]第一句\n[00:05.00]第二句',
              positionStream: const Stream<Duration>.empty(),
              initialPosition: Duration.zero,
              onSeek: seeks.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('第二句'));
    await tester.pump();

    expect(seeks, [const Duration(seconds: 5)]);
    expect(toggles, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开启确认后第一次点按只选中，再次点按同一行才跳转', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricsPanel(
            lyrics: '[00:00.00]第一句\n[00:05.00]第二句',
            positionStream: const Stream<Duration>.empty(),
            initialPosition: Duration.zero,
            onSeek: seeks.add,
            confirmSeek: true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('第二句'));
    await tester.pump();

    // 第一次点按不弹框、不跳转，只给出二次点按提示。
    expect(seeks, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('再次点按跳转到 0:05'), findsOneWidget);

    await tester.tap(find.text('第二句'));
    await tester.pump();

    expect(seeks, [const Duration(seconds: 5)]);
    expect(find.text('再次点按跳转到 0:05'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('二次点按确认时点按另一行会把待确认状态移动到新行', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricsPanel(
            lyrics: '[00:00.00]第一句\n[00:05.00]第二句',
            positionStream: const Stream<Duration>.empty(),
            initialPosition: Duration.zero,
            onSeek: seeks.add,
            confirmSeek: true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('第二句'));
    await tester.pump();
    await tester.tap(find.text('第一句'));
    await tester.pump();

    expect(seeks, isEmpty);
    expect(find.text('再次点按跳转到 0:00'), findsOneWidget);
    expect(find.text('再次点按跳转到 0:05'), findsNothing);

    await tester.tap(find.text('第一句'));
    await tester.pump();

    expect(seeks, [Duration.zero]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换歌词后不再保留待确认状态', (tester) async {
    final seeks = <Duration>[];
    Widget build(String lyrics) => MaterialApp(
      home: Scaffold(
        body: LyricsPanel(
          lyrics: lyrics,
          positionStream: const Stream<Duration>.empty(),
          initialPosition: Duration.zero,
          onSeek: seeks.add,
          confirmSeek: true,
        ),
      ),
    );

    await tester.pumpWidget(build('[00:00.00]第一句\n[00:05.00]第二句'));
    await tester.pump();
    await tester.tap(find.text('第二句'));
    await tester.pump();
    expect(find.text('再次点按跳转到 0:05'), findsOneWidget);

    await tester.pumpWidget(build('[00:00.00]新的第一句\n[00:05.00]新的第二句'));
    await tester.pump();

    expect(find.text('再次点按跳转到 0:05'), findsNothing);
    await tester.tap(find.text('新的第二句'));
    await tester.pump();
    expect(seeks, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭点击定位后歌词行不再响应点击', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LyricsPanel(
            lyrics: '[00:00.00]第一句',
            positionStream: Stream<Duration>.empty(),
            initialPosition: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(LyricsPanel),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });

  testWidgets('设置项可持久化并联动禁用确认开关', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: Scaffold(body: LyricsSettingsSection())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('跳转前确认'));
    await tester.pumpAndSettle();
    expect(
      await database.readSetting(lyricsTapToSeekConfirmSettingKey),
      'true',
    );

    await tester.tap(find.text('点击歌词定位播放进度'));
    await tester.pumpAndSettle();
    expect(await database.readSetting(lyricsTapToSeekSettingKey), 'false');

    final confirmTile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '跳转前确认'),
    );
    expect(confirmTile.onChanged, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });
}
