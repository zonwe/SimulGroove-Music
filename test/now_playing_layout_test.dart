import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_music/app/providers.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/core/player/now_playing_layout.dart';
import 'package:flutter_music/features/settings/now_playing_layout_settings_section.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('播放器布局默认经典并可序列化双栏模式', () {
    expect(parseNowPlayingLayout(null), NowPlayingLayout.classic);
    expect(parseNowPlayingLayout('unknown'), NowPlayingLayout.classic);
    expect(parseNowPlayingLayout('split'), NowPlayingLayout.split);
    expect(serializeNowPlayingLayout(NowPlayingLayout.classic), 'classic');
    expect(serializeNowPlayingLayout(NowPlayingLayout.split), 'split');
  });

  testWidgets('设置项可持久化封面歌词双栏布局', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(
          home: Scaffold(body: NowPlayingLayoutSettingsSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('封面歌词双栏'), findsOneWidget);
    await tester.tap(find.text('封面歌词双栏'));
    await tester.pumpAndSettle();

    expect(await database.readSetting(nowPlayingLayoutSettingKey), 'split');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });
}
