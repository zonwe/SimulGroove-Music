import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import '../log/app_log.dart';
import 'equalizer_models.dart';
import 'playback_queue_logic.dart';

/// 供 just_audio 构建音频管线时挂载的 Android 均衡器实例。
///
/// Android 的均衡器必须先挂进 AudioPipeline 才能在运行时调节，
/// 因此实例与应用生命周期一致，全局只创建一次。
final ja.AndroidEqualizer? sharedAndroidEqualizer =
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? ja.AndroidEqualizer()
    : null;

/// 均衡器的当前生效状态（应用层视角，与平台效果链解耦）。
typedef EqualizerState = ({
  bool enabled,
  String presetId,
  List<double> gains,
  double preampDb,
});

/// 从 AppSettings 解析均衡器配置；增益缺失或损坏时回落到默认预设。
///
/// 启动恢复与均衡器界面初始加载共用此解析，保证两处语义一致。
EqualizerState parseEqualizerSettings(Map<String, String> settings) {
  final enabled = settings['audio.equalizer.enabled'] != 'false';
  final presetId = settings['audio.equalizer.preset'] ?? 'flat';
  final gainsJson = settings['audio.equalizer.gains'];
  final preampStr = settings['audio.equalizer.preamp'];

  var gains = EqualizerPreset.parseGains(gainsJson);
  var preamp = preampStr != null ? (double.tryParse(preampStr) ?? 0.0) : 0.0;
  if (gainsJson == null || gainsJson.isEmpty) {
    final defaultPreset = findDefaultEqualizerPreset(presetId);
    if (defaultPreset != null) {
      gains = List<double>.from(defaultPreset.gains);
      preamp = defaultPreset.preampDb;
    }
  }
  return (enabled: enabled, presetId: presetId, gains: gains, preampDb: preamp);
}

/// 均衡器状态与平台效果的粘合层。
///
/// 从 [MusicAudioHandler] 拆出的职责：保存应用层状态、把增益映射到
/// 各平台的音频效果链。播放编排（队列、循环模式）仍留在 handler。
class EqualizerController {
  bool _enabled = false;
  List<double> _gains = List<double>.filled(10, 0.0);
  double _preampDb = 0.0;
  String _presetId = 'flat';

  bool get enabled => _enabled;
  List<double> get gains => List.unmodifiable(_gains);
  double get preampDb => _preampDb;
  String get presetId => _presetId;

  Future<void> apply({
    required bool enabled,
    required List<double> gains,
    double preampDb = 0.0,
    String? presetId,
  }) async {
    _enabled = enabled;
    _gains = normalizeEqualizerGains(gains);
    _preampDb = preampDb;
    if (presetId != null) _presetId = presetId;
    await _applyToPlatform();
  }

  /// 应用一个具名预设；未知预设（如已删除的自定义预设）保持现状。
  Future<void> applyPreset(String presetId) async {
    final preset = findDefaultEqualizerPreset(presetId);
    if (preset == null) return;
    await apply(
      enabled: _enabled,
      gains: preset.gains,
      preampDb: preset.preampDb,
      presetId: presetId,
    );
  }

  Future<void> _applyToPlatform() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux)) {
      await JustAudioMediaKit.setEqualizerForAll(
        enabled: _enabled,
        gains: _gains,
        preampDb: _preampDb,
      );
      return;
    }
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        sharedAndroidEqualizer != null) {
      try {
        await _applyToAndroid(sharedAndroidEqualizer!);
      } catch (error, stackTrace) {
        // 设备音效不可用或受权限限制时按无声学效果降级，但要留痕。
        AppLog.warning('应用 Android 均衡器失败，已降级为直通', error, stackTrace);
      }
    }
  }

  Future<void> _applyToAndroid(ja.AndroidEqualizer equalizer) async {
    await equalizer.setEnabled(_enabled);
    if (!_enabled) return;
    final params = await equalizer.parameters;
    final minDecibels = params.minDecibels;
    final maxDecibels = params.maxDecibels;
    final bands = params.bands;
    if (bands.isEmpty) return;
    for (var i = 0; i < bands.length; i++) {
      final gainIndex = equalizerBandGainIndex(
        bandIndex: i,
        bandCount: bands.length,
        gainCount: _gains.length,
      );
      final targetGain = _gains[gainIndex] + _preampDb;
      await bands[i].setGain(
        targetGain.clamp(minDecibels, maxDecibels).toDouble(),
      );
    }
  }
}
