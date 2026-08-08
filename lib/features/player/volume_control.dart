import 'package:flutter/material.dart';

import '../../core/player/music_audio_handler.dart';

/// Shared volume control. The icon toggles mute and the optional slider keeps
/// adjustment inline instead of opening a secondary page or dialog.
class VolumeControl extends StatelessWidget {
  const VolumeControl({
    super.key,
    required this.handler,
    this.showSlider = true,
  });

  final MusicAudioHandler handler;
  final bool showSlider;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: handler.volumeStream,
      initialData: 1,
      builder: (context, snapshot) {
        final volume = (snapshot.data ?? 1).clamp(0.0, 1.0).toDouble();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: volume <= 0 ? '取消静音' : '静音',
              onPressed: handler.toggleMute,
              icon: Icon(_volumeIcon(volume)),
            ),
            if (showSlider)
              SizedBox(
                width: 132,
                child: Slider(
                  value: volume,
                  onChanged: handler.setVolume,
                  semanticFormatterCallback: (value) =>
                      '音量 ${(value * 100).round()}%',
                ),
              ),
          ],
        );
      },
    );
  }
}

IconData _volumeIcon(double volume) {
  if (volume <= 0) return Icons.volume_off_rounded;
  if (volume < 0.5) return Icons.volume_down_rounded;
  return Icons.volume_up_rounded;
}
