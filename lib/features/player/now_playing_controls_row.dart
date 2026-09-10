import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../core/player/music_audio_handler.dart';
import 'now_playing_playback_mode.dart';
import 'track_info_sheet.dart';
import 'volume_control.dart';

/// 正在播放页底部控制行：上一首/播放暂停/下一首、播放模式、音量与曲目信息。
///
/// 布局差异：Android 左侧播放模式、右侧曲目信息；桌面端把播放模式并入
/// 主控右侧，音量与曲目信息靠右。
class NowPlayingControlsRow extends StatelessWidget {
  const NowPlayingControlsRow({
    super.key,
    required this.handler,
    required this.item,
    required this.isAndroid,
    required this.isDesktop,
    required this.docked,
    required this.showTrackInfoButton,
  });

  final MusicAudioHandler handler;
  final MediaItem item;
  final bool isAndroid;
  final bool isDesktop;
  final bool docked;
  final bool showTrackInfoButton;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      initialData: handler.playbackState.value,
      builder: (context, snapshot) {
        final state = snapshot.data ?? handler.playbackState.value;
        final playing = state.playing;
        final playbackMode = playbackModeFromState(state);
        final compactControls =
            isAndroid || docked || MediaQuery.sizeOf(context).width < 760;
        final modeButton = IconButton(
          tooltip: playbackModeLabel(playbackMode),
          onPressed: () =>
              handler.setPlaybackMode(nextPlaybackMode(playbackMode)),
          icon: Icon(
            playbackModeIcon(playbackMode),
            color: Theme.of(context).colorScheme.primary,
          ),
        );
        final infoButton = TrackInfoButton(item: item);
        final trailingControls = isDesktop
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showTrackInfoButton) infoButton,
                  VolumeControl(handler: handler, showSlider: !compactControls),
                ],
              )
            : const SizedBox.shrink();
        final leftControls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [if (!isDesktop) modeButton],
        );
        final primaryControls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              iconSize: 30,
              tooltip: '上一首',
              onPressed: handler.skipToPrevious,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            SizedBox(width: compactControls ? 8 : 22),
            IconButton.filled(
              iconSize: 38,
              tooltip: playing ? '暂停' : '播放',
              onPressed: playing ? handler.pause : handler.play,
              icon: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            ),
            SizedBox(width: compactControls ? 8 : 22),
            IconButton.filledTonal(
              iconSize: 30,
              tooltip: '下一首',
              onPressed: handler.skipToNext,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            if (isDesktop) ...[
              SizedBox(width: compactControls ? 4 : 10),
              modeButton,
            ],
          ],
        );
        if (isAndroid) {
          return Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: modeButton,
                ),
              ),
              primaryControls,
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: infoButton,
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: leftControls,
              ),
            ),
            SizedBox(width: compactControls ? 8 : 20),
            primaryControls,
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: trailingControls,
              ),
            ),
          ],
        );
      },
    );
  }
}
