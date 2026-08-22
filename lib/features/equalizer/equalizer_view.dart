import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/player/equalizer_models.dart';

class EqualizerView extends ConsumerStatefulWidget {
  const EqualizerView({super.key});

  static Future<void> show(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭均衡器',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 90),
      pageBuilder: (ctx, anim1, anim2) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: EqualizerView(),
      ),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(curve),
            child: child,
          ),
        );
      },
    );
  }

  @override
  ConsumerState<EqualizerView> createState() => _EqualizerViewState();
}

class _EqualizerViewState extends ConsumerState<EqualizerView> {
  final _uuid = const Uuid();
  Timer? _debounceTimer;

  bool _enabled = true;
  String _selectedPresetId = 'flat';
  List<double> _gains = List<double>.filled(10, 0.0);
  double _preampDb = 0.0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialState() async {
    final db = ref.read(databaseProvider);
    final settings = await db.watchSettings().first;

    final enabled = settings['audio.equalizer.enabled'] != 'false';
    final presetId = settings['audio.equalizer.preset'] ?? 'flat';
    final gainsJson = settings['audio.equalizer.gains'];
    final preampStr = settings['audio.equalizer.preamp'];

    var gains = EqualizerPreset.parseGains(gainsJson);
    var preamp = preampStr != null ? (double.tryParse(preampStr) ?? 0.0) : 0.0;

    // If gains were empty and preset is a default preset, load default preset gains
    if (gainsJson == null || gainsJson.isEmpty) {
      final defaultPreset = findDefaultEqualizerPreset(presetId);
      if (defaultPreset != null) {
        gains = List<double>.from(defaultPreset.gains);
        preamp = defaultPreset.preampDb;
      }
    }

    if (mounted) {
      setState(() {
        _enabled = enabled;
        _selectedPresetId = presetId;
        _gains = List<double>.from(gains);
        _preampDb = preamp;
        _initialized = true;
      });
    }

    // Apply to audio handler
    ref
        .read(audioHandlerProvider)
        .applyEqualizer(
          enabled: enabled,
          gains: _gains,
          preampDb: _preampDb,
          presetId: _selectedPresetId,
        );
  }

  void _onGainsChanged({bool debounced = true}) {
    final handler = ref.read(audioHandlerProvider);
    if (debounced) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 50), () {
        handler.applyEqualizer(
          enabled: _enabled,
          gains: _gains,
          preampDb: _preampDb,
          presetId: _selectedPresetId,
        );
      });
    } else {
      handler.applyEqualizer(
        enabled: _enabled,
        gains: _gains,
        preampDb: _preampDb,
        presetId: _selectedPresetId,
      );
    }
    _persistSettings();
  }

  Future<void> _persistSettings() async {
    final db = ref.read(databaseProvider);
    await db.setSetting('audio.equalizer.enabled', _enabled.toString());
    await db.setSetting('audio.equalizer.preset', _selectedPresetId);
    await db.setSetting('audio.equalizer.gains', jsonEncode(_gains));
    await db.setSetting('audio.equalizer.preamp', _preampDb.toStringAsFixed(1));
  }

  void _selectPreset(EqualizerPreset preset) {
    setState(() {
      _selectedPresetId = preset.id;
      _gains = List<double>.from(preset.gains);
      _preampDb = preset.preampDb;
    });
    _onGainsChanged(debounced: false);
  }

  void _resetToFlat() {
    setState(() {
      _selectedPresetId = 'flat';
      _gains = List<double>.filled(10, 0.0);
      _preampDb = 0.0;
    });
    _onGainsChanged(debounced: false);
  }

  Future<void> _saveAsNewPreset() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存自定义预设'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '预设名称',
            hintText: '如：我的专属调音',
            border: OutlineInputBorder(),
          ),
          maxLength: 24,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.of(ctx).pop(text);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final db = ref.read(databaseProvider);
      final id = _uuid.v4();
      final now = DateTime.now();
      final currentAccount = await db.watchCurrentAccount().first;

      await db.saveEqualizerPreset(
        EqualizerPresetsCompanion.insert(
          id: id,
          remoteId: drift.Value('preset-$id'),
          accountId: drift.Value(currentAccount?.id),
          name: name,
          gainsJson: jsonEncode(_gains),
          preampDb: drift.Value(_preampDb),
          createdAt: now,
          updatedAt: now,
        ),
      );

      setState(() {
        _selectedPresetId = id;
      });
      _persistSettings();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已保存预设 “$name”')));
      }
    }
  }

  Future<void> _updateCurrentCustomPreset(EqualizerPreset customPreset) async {
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    await db.saveEqualizerPreset(
      EqualizerPresetsCompanion.insert(
        id: customPreset.id,
        remoteId: drift.Value(
          customPreset.remoteId ?? 'preset-${customPreset.id}',
        ),
        name: customPreset.name,
        gainsJson: jsonEncode(_gains),
        preampDb: drift.Value(_preampDb),
        createdAt: customPreset.updatedAt ?? now,
        updatedAt: now,
      ),
    );
    _persistSettings();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已更新预设 “${customPreset.name}”')));
    }
  }

  Future<void> _deleteCustomPreset(EqualizerPreset customPreset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除预设'),
        content: Text('确定要删除自定义预设 “${customPreset.name}” 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(databaseProvider);
      await db.deleteEqualizerPreset(customPreset.id);
      _resetToFlat();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已删除预设 “${customPreset.name}”')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customPresetsAsync = ref.watch(customEqualizerPresetsProvider);
    final customPresets = customPresetsAsync.value ?? const [];

    EqualizerPreset? currentCustomPreset;
    for (final p in customPresets) {
      if (p.id == _selectedPresetId) {
        currentCustomPreset = p;
        break;
      }
    }

    // Check potential clipping (max gain + preamp > 0)
    final maxGain = _gains.fold<double>(0.0, (m, g) => math.max(m, g));
    final hasClippingRisk = (_enabled && (maxGain + _preampDb > 1.0));

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: math.min(MediaQuery.sizeOf(context).height * 0.88, 700),
        ),
        child: Material(
          color: colorScheme.surface,
          elevation: 6,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.7,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.equalizer_rounded,
                        color: colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '图形均衡器',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _enabled ? '10 频段实时 DSP 音效调节' : '均衡器已禁用',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Master Enable Switch
                    Switch(
                      value: _enabled,
                      onChanged: (val) {
                        setState(() => _enabled = val);
                        _onGainsChanged(debounced: false);
                      },
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              Expanded(
                child: !_initialized
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Preset Selector Row
                            _buildPresetRow(
                              colorScheme,
                              customPresets,
                              currentCustomPreset,
                            ),

                            const SizedBox(height: 16),

                            // Visual Curve Display
                            Container(
                              height: 120,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: CustomPaint(
                                  painter: EqualizerCurvePainter(
                                    gains: _gains,
                                    enabled: _enabled,
                                    primaryColor: colorScheme.primary,
                                    gridColor: colorScheme.outlineVariant,
                                  ),
                                  child: Container(),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Sliders Group
                            Container(
                              padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  for (var i = 0; i < 10; i++)
                                    _buildBandSlider(
                                      index: i,
                                      freqLabel: equalizerFrequencyLabels[i],
                                      gain: _gains[i],
                                      colorScheme: colorScheme,
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Preamp & Clipping Alert
                            _buildPreampSection(colorScheme, hasClippingRisk),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetRow(
    ColorScheme colorScheme,
    List<EqualizerPreset> customPresets,
    EqualizerPreset? currentCustomPreset,
  ) {
    final allPresets = <EqualizerPreset>[
      ...defaultEqualizerPresets,
      ...customPresets,
    ];

    return Row(
      children: [
        // Dropdown
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(_selectedPresetId),
            initialValue: allPresets.any((p) => p.id == _selectedPresetId)
                ? _selectedPresetId
                : 'flat',
            decoration: InputDecoration(
              labelText: '预设配置',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.tune_rounded, size: 20),
            ),

            items: [
              const DropdownMenuItem(
                enabled: false,
                child: Text(
                  '—— 默认预设 ——',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              for (final p in defaultEqualizerPresets)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
              if (customPresets.isNotEmpty) ...[
                const DropdownMenuItem(
                  enabled: false,
                  child: Text(
                    '—— 我的自定义预设 ——',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                for (final p in customPresets)
                  DropdownMenuItem(value: p.id, child: Text('★ ${p.name}')),
              ],
            ],
            onChanged: (val) {
              if (val == null) return;
              final found = allPresets.firstWhere(
                (p) => p.id == val,
                orElse: () => defaultEqualizerPresets.first,
              );
              _selectPreset(found);
            },
          ),
        ),

        const SizedBox(width: 8),

        // Action menu / Save button
        PopupMenuButton<String>(
          tooltip: '预设操作',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (action) {
            switch (action) {
              case 'save_new':
                _saveAsNewPreset();
                break;
              case 'update_current':
                if (currentCustomPreset != null) {
                  _updateCurrentCustomPreset(currentCustomPreset);
                }
                break;
              case 'delete_current':
                if (currentCustomPreset != null) {
                  _deleteCustomPreset(currentCustomPreset);
                }
                break;
              case 'reset_flat':
                _resetToFlat();
                break;
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: 'save_new',
              child: ListTile(
                leading: Icon(Icons.add_circle_outline_rounded),
                title: Text('保存为新预设'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (currentCustomPreset != null) ...[
              const PopupMenuItem(
                value: 'update_current',
                child: ListTile(
                  leading: Icon(Icons.save_outlined),
                  title: Text('覆盖更新当前预设'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete_current',
                child: ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red,
                  ),
                  title: Text('删除此自定义预设', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            const PopupMenuItem(
              value: 'reset_flat',
              child: ListTile(
                leading: Icon(Icons.restart_alt_rounded),
                title: Text('归零重置 (平直)'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBandSlider({
    required int index,
    required String freqLabel,
    required double gain,
    required ColorScheme colorScheme,
  }) {
    final gainText = gain > 0
        ? '+${gain.toStringAsFixed(1)}'
        : gain.toStringAsFixed(1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Gain value badge
        GestureDetector(
          onTap: () {
            // Quick reset to 0dB
            setState(() => _gains[index] = 0.0);
            _onGainsChanged();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: gain != 0.0 && _enabled
                  ? colorScheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              gainText,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: gain != 0.0 && _enabled
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
                activeTrackColor: _enabled
                    ? colorScheme.primary
                    : colorScheme.outline,
                inactiveTrackColor: colorScheme.outlineVariant.withValues(
                  alpha: 0.4,
                ),
                thumbColor: _enabled
                    ? colorScheme.primary
                    : colorScheme.outline,
              ),
              child: Slider(
                value: gain.clamp(-12.0, 12.0),
                min: -12.0,
                max: 12.0,
                divisions: 48,
                onChanged: _enabled
                    ? (val) {
                        setState(() {
                          _gains[index] = val;
                        });
                        _onGainsChanged();
                      }
                    : null,
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

  Widget _buildPreampSection(ColorScheme colorScheme, bool hasClippingRisk) {
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
                '${_preampDb > 0 ? '+' : ''}${_preampDb.toStringAsFixed(1)} dB',
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
              value: _preampDb.clamp(-12.0, 0.0),
              min: -12.0,
              max: 0.0,
              divisions: 24,
              onChanged: _enabled
                  ? (val) {
                      setState(() => _preampDb = val);
                      _onGainsChanged();
                    }
                  : null,
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

class EqualizerCurvePainter extends CustomPainter {
  EqualizerCurvePainter({
    required this.gains,
    required this.enabled,
    required this.primaryColor,
    required this.gridColor,
  });

  final List<double> gains;
  final bool enabled;
  final Color primaryColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final midY = height / 2;

    final dashPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.7)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 0dB Center line
    canvas.drawLine(Offset(0, midY), Offset(width, midY), dashPaint);

    if (gains.isEmpty) return;

    // Convert gains to canvas points
    final points = <Offset>[];
    final step = width / (gains.length - 1);

    for (var i = 0; i < gains.length; i++) {
      final x = i * step;
      // Map gain [-12, +12] to y [height - 8, 8]
      final g = enabled ? gains[i].clamp(-12.0, 12.0) : 0.0;
      final y = midY - (g / 12.0) * (midY - 12);
      points.add(Offset(x, y));
    }

    // Build smooth cubic bezier curve
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      path.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }

    // Fill area under curve with gradient
    final fillPath = Path.from(path)
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (enabled ? primaryColor : Colors.grey).withValues(alpha: 0.35),
          (enabled ? primaryColor : Colors.grey).withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, width, height));

    canvas.drawPath(fillPath, fillPaint);

    // Stroke line
    final linePaint = Paint()
      ..color = enabled ? primaryColor : Colors.grey
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    // Draw dots at control points
    final dotPaint = Paint()
      ..color = enabled ? primaryColor : Colors.grey
      ..style = PaintingStyle.fill;

    for (final point in points) {
      canvas.drawCircle(point, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant EqualizerCurvePainter oldDelegate) {
    return oldDelegate.enabled != enabled ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.gains != gains;
  }
}
