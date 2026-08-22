import 'dart:convert';

const List<int> equalizerFrequencies = [
  31,
  62,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

const List<String> equalizerFrequencyLabels = [
  '31Hz',
  '62Hz',
  '125Hz',
  '250Hz',
  '500Hz',
  '1kHz',
  '2kHz',
  '4kHz',
  '8kHz',
  '16kHz',
];

class EqualizerPreset {
  const EqualizerPreset({
    required this.id,
    required this.name,
    required this.gains,
    this.preampDb = 0.0,
    this.isCustom = false,
    this.remoteId,
    this.updatedAt,
  });

  final String id;
  final String name;
  final List<double> gains;
  final double preampDb;
  final bool isCustom;
  final String? remoteId;
  final DateTime? updatedAt;

  String get gainsJson => jsonEncode(gains);

  static List<double> parseGains(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) {
      return List<double>.filled(10, 0.0);
    }
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        final list = decoded.map((e) => (e as num).toDouble()).toList();
        if (list.length < 10) {
          list.addAll(List<double>.filled(10 - list.length, 0.0));
        }
        return list.take(10).toList();
      }
    } catch (_) {}
    return List<double>.filled(10, 0.0);
  }

  EqualizerPreset copyWith({
    String? id,
    String? name,
    List<double>? gains,
    double? preampDb,
    bool? isCustom,
    String? remoteId,
    DateTime? updatedAt,
  }) => EqualizerPreset(
    id: id ?? this.id,
    name: name ?? this.name,
    gains: gains ?? this.gains,
    preampDb: preampDb ?? this.preampDb,
    isCustom: isCustom ?? this.isCustom,
    remoteId: remoteId ?? this.remoteId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

const List<EqualizerPreset> defaultEqualizerPresets = [
  EqualizerPreset(
    id: 'flat',
    name: '平直',
    gains: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    preampDb: 0.0,
  ),
  EqualizerPreset(
    id: 'pop',
    name: '流行',
    gains: [-1.5, -1.0, 0.0, 2.0, 4.0, 3.5, 1.5, 0.0, -1.0, -1.5],
    preampDb: -1.0,
  ),
  EqualizerPreset(
    id: 'rock',
    name: '摇滚',
    gains: [4.5, 3.5, 2.0, 0.0, -1.5, -1.0, 1.5, 3.0, 4.0, 4.5],
    preampDb: -2.0,
  ),
  EqualizerPreset(
    id: 'bass',
    name: '低音增强',
    gains: [6.0, 5.0, 3.5, 1.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    preampDb: -3.0,
  ),
  EqualizerPreset(
    id: 'vocal',
    name: '人声增强',
    gains: [-2.0, -1.5, -1.0, 1.0, 3.5, 4.5, 3.0, 1.5, 0.0, -1.0],
    preampDb: -1.5,
  ),
  EqualizerPreset(
    id: 'classical',
    name: '古典',
    gains: [3.5, 3.0, 2.5, 1.5, -0.5, -0.5, 0.0, 2.0, 3.0, 3.5],
    preampDb: -1.5,
  ),
  EqualizerPreset(
    id: 'jazz',
    name: '爵士',
    gains: [2.5, 2.0, 1.0, 1.5, -1.0, -1.0, 0.0, 1.5, 2.5, 3.0],
    preampDb: -1.0,
  ),
  EqualizerPreset(
    id: 'electronic',
    name: '电子乐',
    gains: [5.0, 4.0, 2.0, 0.0, -2.0, 1.5, 0.5, 2.5, 4.0, 4.5],
    preampDb: -2.5,
  ),
  EqualizerPreset(
    id: 'acoustic',
    name: '原声民谣',
    gains: [2.0, 1.5, 1.0, 0.5, 1.0, 1.5, 2.0, 2.5, 2.0, 1.5],
    preampDb: -1.0,
  ),
];

EqualizerPreset? findDefaultEqualizerPreset(String id) {
  for (final preset in defaultEqualizerPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
