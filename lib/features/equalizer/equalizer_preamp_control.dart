import 'package:flutter/material.dart';

/// 前级增益控制与数字削波提示。
class EqualizerPreampControl extends StatelessWidget {
  const EqualizerPreampControl({
    super.key,
    required this.preampDb,
    required this.enabled,
    required this.hasClippingRisk,
    required this.onChanged,
  });

  final double preampDb;
  final bool enabled;
  final bool hasClippingRisk;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.volume_down_rounded, size: 18),
              const SizedBox(width: 8),
              Text(
                '前级增益 (Preamp)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${preampDb > 0 ? '+' : ''}${preampDb.toStringAsFixed(1)} dB',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: preampDb.clamp(-12.0, 0.0),
              min: -12.0,
              max: 0.0,
              divisions: 24,
              onChanged: enabled ? onChanged : null,
            ),
          ),
          if (hasClippingRisk)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '提示：低频/高频提升较多，适当调低前级增益可防止数字削波破音。',
                      style: TextStyle(fontSize: 11, color: colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
