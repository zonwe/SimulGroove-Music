import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/online_music/online_music_error.dart';
import '../../core/online_music/online_track_persistence.dart';
import '../../core/player/track_availability.dart';
import 'now_playing_page.dart';

Future<void> playOrOpenNowPlaying(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks, {
  required int initialIndex,
}) async {
  if (tracks.isEmpty || initialIndex < 0 || initialIndex >= tracks.length) {
    return;
  }
  final handler = ref.read(audioHandlerProvider);
  final selected = tracks[initialIndex];
  final onlineTrack = onlineTrackFromDatabase(selected);
  if (onlineTrack != null) {
    if (handler.mediaItem.value?.id != selected.id) {
      try {
        await ref.read(onlineTrackPlaybackProvider).play(onlineTrack);
      } catch (error) {
        if (!context.mounted) return;
        final message = error is OnlineMusicException
            ? error.message
            : '在线播放失败，请稍后重试。';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        return;
      }
    }
    if (!context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NowPlayingPage()));
    return;
  }
  final reason = await checkTrackAvailability(selected);
  if (!context.mounted) {
    return;
  }
  if (reason != null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('无法播放：$reason')));
    return;
  }
  if (handler.mediaItem.value?.id == selected.id) {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NowPlayingPage()));
    return;
  }
  final playableTracks = <Track>[];
  for (final track in tracks) {
    if (await checkTrackAvailability(track) == null) {
      playableTracks.add(track);
    }
  }
  final playableIndex = playableTracks.indexWhere(
    (track) => track.id == selected.id,
  );
  if (playableIndex < 0) return;
  try {
    await handler.playTracks(playableTracks, initialIndex: playableIndex);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法播放：$error')));
    }
  }
}
