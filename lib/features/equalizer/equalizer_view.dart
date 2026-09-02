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
import 'equalizer_band_slider.dart';
import 'equalizer_curve_painter.dart';
import 'equalizer_preamp_control.dart';
import 'equalizer_preset_selector.dart';

export 'equalizer_curve_painter.dart' show EqualizerCurvePainter;

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

  void _onPresetAction(EqualizerPresetAction action) {
    final currentCustomPreset = _currentCustomPreset();
    switch (action) {
      case EqualizerPresetAction.saveNew:
        _saveAsNewPreset();
      case EqualizerPresetAction.updateCurrent:
        if (currentCustomPreset != null) {
          _updateCurrentCustomPreset(currentCustomPreset);
        }
      case EqualizerPresetAction.deleteCurrent:
        if (currentCustomPreset != null) {
          _deleteCustomPreset(currentCustomPreset);
        }
      case EqualizerPresetAction.resetFlat:
        _resetToFlat();
    }
  }

  EqualizerPreset? _currentCustomPreset() {
    final customPresets = ref.read(customEqualizerPresetsProvider).value;
    if (customPresets == null) return null;
    for (final p in customPresets) {
      if (p.id == _selectedPresetId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customPresets =
        ref.watch(customEqualizerPresetsProvider).value ?? const [];

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
                            EqualizerPresetSelector(
                              selectedPresetId: _selectedPresetId,
                              customPresets: customPresets,
                              currentCustomPreset: _currentCustomPreset(),
                              onSelect: _selectPreset,
                              onAction: _onPresetAction,
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
                                    EqualizerBandSlider(
                                      freqLabel: equalizerFrequencyLabels[i],
                                      gain: _gains[i],
                                      enabled: _enabled,
                                      onGainChanged: (val) {
                                        setState(() => _gains[i] = val);
                                        _onGainsChanged();
                                      },
                                      onReset: () {
                                        setState(() => _gains[i] = 0.0);
                                        _onGainsChanged();
                                      },
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Preamp & Clipping Alert
                            EqualizerPreampControl(
                              preampDb: _preampDb,
                              enabled: _enabled,
                              hasClippingRisk: hasClippingRisk,
                              onChanged: (val) {
                                setState(() => _preampDb = val);
                                _onGainsChanged();
                              },
                            ),
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
}
