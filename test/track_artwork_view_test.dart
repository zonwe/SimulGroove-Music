import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_music/app/providers.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/features/library/artwork_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  testWidgets('按曲目 id 取封面，没有封面时回退到占位图', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.upsertTracks(
      [
        TracksCompanion.insert(
          id: 'with-cover',
          sourceType: 'test',
          sourceId: 'with-cover',
          uri: 'test://with-cover',
          title: 'with-cover',
          updatedAt: DateTime(2026),
        ),
      ],
      artworks: {'with-cover': _pngBytes()},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TrackArtworkView(trackId: 'with-cover'),
                TrackArtworkView(trackId: 'no-cover'),
                TrackArtworkView(trackId: null),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.music_note_rounded), findsNWidgets(2));
  });

  testWidgets('显式传入的封面优先于数据库查询', (tester) async {
    // 队列里已经缓存过封面的曲目（例如在线播放）不应再查库。
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TrackArtworkView(
              trackId: 'online:source:1',
              bytes: _pngBytes(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Uint8List _pngBytes() =>
    Uint8List.fromList(image.encodePng(image.Image(width: 2, height: 2)));
