import 'package:flutter/material.dart';

/// 单个均衡器频段的垂直滑杆；点击增益徽标快速归零。
class EqualizerBandSlider extends StatelessWidget {
  const EqualizerBandSlider({
    super.key,
    required this.freqLabel,
    required this.gain,
    required this.enabled,
    required this.onGainChanged,
    required this.onReset,
  });

  final String freqLabel;
  final double gain;
  final bool enabled;
  final ValueChanged<double> onGainChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final gainText = gain > 0
        ? '+${gain.toStringAsFixed(1)}'
        : gain.toStringAsFixed(1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Gain value badge
        GestureDetector(
          onTap: onReset,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: gain != 0.0 && enabled
                  ? colorScheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              gainText,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: gain != 0.0 && enabled
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),

        const SizedBox(height: 4),

        // Vertical Slider
        SizedBox(
          height: 170,
          width: 32,
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: enabled
                    ? colorScheme.primary
                    : colorScheme.outline,
                inactiveTrackColor: colorScheme.outlineVariant.withValues(
                  alpha: 0.4,
                ),
                thumbColor: enabled ? colorScheme.primary : colorScheme.outline,
              ),
              child: Slider(
                value: gain.clamp(-12.0, 12.0),
                min: -12.0,
                max: 12.0,
                divisions: 48,
                onChanged: enabled ? onGainChanged : null,
              ),
            ),
          ),
        ),

        const SizedBox(height: 4),

        // Frequency Label
        Text(
          freqLabel,
          style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
