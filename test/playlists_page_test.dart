import 'package:flutter/material.dart';
import 'package:flutter_music/features/playlists/playlists_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'create playlist dialog can be dismissed by tapping the barrier',
    (tester) async {
      String? result = 'not completed';

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showCreatePlaylistDialog(context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('create playlist dialog returns the trimmed name', (
    tester,
  ) async {
    String? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showCreatePlaylistDialog(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Road Trip  ');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(result, 'Road Trip');
    expect(tester.takeException(), isNull);
  });
}
