import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import 'now_playing_page.dart';

Future<void> playOrOpenNowPlaying(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks, {
  required int initialIndex,
}) async {
  if (tracks.isEmpty) return;
  final handler = ref.read(audioHandlerProvider);
  final selected = tracks[initialIndex];
  if (handler.mediaItem.value?.id == selected.id) {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NowPlayingPage()));
    return;
  }
  await handler.playTracks(tracks, initialIndex: initialIndex);
}
