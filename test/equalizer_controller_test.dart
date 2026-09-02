import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_music/core/player/equalizer_controller.dart';
import 'package:flutter_music/core/player/volume_state.dart';

void main() {
  group('parseEqualizerSettings', () {
    test('完整设置按存储值解析', () {
      final config = parseEqualizerSettings({
        'audio.equalizer.enabled': 'false',
        'audio.equalizer.preset': 'bass',
        'audio.equalizer.gains': '[1,2,3,4,5,6,7,8,9,10]',
        'audio.equalizer.preamp': '-3.0',
      });

      expect(config.enabled, isFalse);
      expect(config.presetId, 'bass');
      expect(config.gains, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(config.preampDb, -3.0);
    });

    test('增益缺失时回落到默认预设', () {
      final config = parseEqualizerSettings({'audio.equalizer.preset': 'bass'});

      expect(config.gains, isNotEmpty);
      expect(config.gains.length, 10);
      expect(config.preampDb, isNot(0));
    });

    test('完全缺失时按开启 + 平直预设兜底', () {
      final config = parseEqualizerSettings(const {});

      expect(config.enabled, isTrue);
      expect(config.presetId, 'flat');
      expect(config.gains, List<double>.filled(10, 0.0));
      expect(config.preampDb, 0.0);
    });

    test('未知预设且增益缺失时增益为平直', () {
      final config = parseEqualizerSettings({
        'audio.equalizer.preset': 'deleted-custom',
      });

      expect(config.presetId, 'deleted-custom');
      expect(config.gains, List<double>.filled(10, 0.0));
    });
  });

  group('resolveVolumeChange', () {
    test('正音量解除静音并更新基准', () {
      final snapshot = resolveVolumeChange(
        requested: 0.6,
        volumeBeforeMute: 0.2,
      );

      expect(snapshot.applied, 0.6);
      expect(snapshot.volumeBeforeMute, 0.6);
      expect(snapshot.muted, isFalse);
    });

    test('0 音量进入静音且不改基准', () {
      final snapshot = resolveVolumeChange(requested: 0, volumeBeforeMute: 0.4);

      expect(snapshot.applied, 0);
      expect(snapshot.volumeBeforeMute, 0.4);
      expect(snapshot.muted, isTrue);
    });

    test('超出范围的音量被收敛到 0..1', () {
      expect(
        resolveVolumeChange(requested: 2, volumeBeforeMute: 0.5).applied,
        1.0,
      );
      expect(
        resolveVolumeChange(requested: -1, volumeBeforeMute: 0.5).applied,
        0,
      );
    });
  });

  group('resolveMuteToggle', () {
    test('非静音时切换进入静音并记录当前音量为基准', () {
      final snapshot = resolveMuteToggle(
        muted: false,
        currentVolume: 0.7,
        volumeBeforeMute: 0.5,
      );

      expect(snapshot.applied, 0);
      expect(snapshot.volumeBeforeMute, 0.7);
      expect(snapshot.muted, isTrue);
    });

    test('静音中切换恢复基准音量', () {
      final snapshot = resolveMuteToggle(
        muted: true,
        currentVolume: 0,
        volumeBeforeMute: 0.5,
      );

      expect(snapshot.applied, 0.5);
      expect(snapshot.muted, isFalse);
    });

    test('音量为 0 但未标记静音时切换同样恢复基准', () {
      final snapshot = resolveMuteToggle(
        muted: false,
        currentVolume: 0,
        volumeBeforeMute: 0.3,
      );

      expect(snapshot.applied, 0.3);
      expect(snapshot.muted, isFalse);
    });

    test('恢复时基准音量不会低于最小可听音量', () {
      final snapshot = resolveMuteToggle(
        muted: true,
        currentVolume: 0,
        volumeBeforeMute: 0,
      );

      expect(snapshot.applied, 0.05);
    });
  });
}
