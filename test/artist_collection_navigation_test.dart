import 'package:flutter/material.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/features/library/collection_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lets the user choose each listed artist', (tester) async {
    final track = _track('鸣潮先锋电台/Casey Lee Williams');

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  openArtistCollectionPage(context, [track], track.artist),
              child: const Text('查看歌手'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('查看歌手'));
    await tester.pumpAndSettle();

    expect(find.text('选择歌手'), findsOneWidget);
    expect(find.text('鸣潮先锋电台'), findsOneWidget);
    expect(find.text('Casey Lee Williams'), findsOneWidget);

    await tester.tap(find.text('Casey Lee Williams'));
    await tester.pumpAndSettle();

    expect(find.byType(CollectionPage), findsOneWidget);
    expect(find.text('Casey Lee Williams'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens a single-artist collection directly', (tester) async {
    final track = _track('Casey Lee Williams');

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  openArtistCollectionPage(context, [track], track.artist),
              child: const Text('查看歌手'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('查看歌手'));
    await tester.pumpAndSettle();

    expect(find.byType(SimpleDialog), findsNothing);
    expect(find.byType(CollectionPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Track _track(String artist) => Track(
  id: 'track-id',
  sourceType: 'test',
  sourceId: 'source-id',
  uri: 'test://track-id',
  title: 'Song',
  artist: artist,
  album: 'Album',
  isAvailable: true,
  syncState: 'local',
  updatedAt: DateTime(2026),
);
