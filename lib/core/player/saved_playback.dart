import 'dart:convert';

import 'package:audio_service/audio_service.dart';

/// Persist stable local IDs only: stream URLs, tickets and headers never belong
/// in a playback snapshot. Both orders let shuffle be disabled after restart.
class SavedPlayback {
  SavedPlayback({
    required Iterable<String> baseIds,
    required Iterable<String> queueIds,
    required this.currentId,
    required this.position,
    required this.repeatMode,
    required this.shuffle,
  }) : baseIds = List.unmodifiable(baseIds),
       queueIds = List.unmodifiable(queueIds);

  final List<String> baseIds;
  final List<String> queueIds;
  final String currentId;
  final Duration position;
  final AudioServiceRepeatMode repeatMode;
  final bool shuffle;

  String get queueJson =>
      jsonEncode({'version': 1, 'base': baseIds, 'queue': queueIds});

  static SavedPlayback? decode({
    required String queueJson,
    required String? currentId,
    required int positionMs,
    required String repeatMode,
    required bool shuffle,
  }) {
    try {
      final json = jsonDecode(queueJson);
      if (json is! Map<String, dynamic> ||
          json['version'] != 1 ||
          currentId == null) {
        return null;
      }
      final base = json['base'];
      final queue = json['queue'];
      if (base is! List ||
          queue is! List ||
          base.isEmpty ||
          base.any((id) => id is! String || id.isEmpty) ||
          queue.any((id) => id is! String || id.isEmpty)) {
        return null;
      }
      final baseIds = base.cast<String>().toSet();
      final queueIds = queue.cast<String>().toSet();
      if (baseIds.length != base.length ||
          queueIds.length != queue.length ||
          !baseIds.containsAll(queueIds) ||
          !queueIds.containsAll(baseIds) ||
          !queueIds.contains(currentId)) {
        return null;
      }
      return SavedPlayback(
        baseIds: baseIds,
        queueIds: queueIds,
        currentId: currentId,
        position: Duration(milliseconds: positionMs < 0 ? 0 : positionMs),
        repeatMode: AudioServiceRepeatMode.values.firstWhere(
          (mode) => mode.name == repeatMode,
          orElse: () => AudioServiceRepeatMode.none,
        ),
        shuffle: shuffle,
      );
    } on FormatException {
      return null;
    }
  }
}
