import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../log/app_log.dart';
import '../notifications/scan_notification_service.dart';
import 'library_scanner.dart';
import 'scanned_track.dart';

const scanNotificationEnabledSettingKey = 'library.scan_notification_enabled';

enum LibraryScanOperation { scan, rescan, delete }

class LibraryScanController extends ChangeNotifier {
  LibraryScanController(this._database, this._scanner, this._notifications);

  final AppDatabase _database;
  final LibraryScanner _scanner;
  final ScanNotificationService _notifications;
  LibraryScanOperation? _operation;
  String? _message;
  bool _hasError = false;
  bool _disposed = false;

  bool get busy => operation != null;
  LibraryScanOperation? get operation => _operation;
  String? get message => _message;
  bool get hasError => _hasError;

  Future<void> scan({bool fullDevice = false}) =>
      _run(LibraryScanOperation.scan, fullDevice ? '整台设备' : '音乐文件夹', () async {
        final result = fullDevice
            ? await _scanner.scanFullDevice()
            : await _scanner.scan();
        if (result == null) return null;
        await _database.transaction(() async {
          await _database.upsertTracks(result.tracks.map(_toCompanion));
          await _saveSource(result);
        });
        return (
          count: result.tracks.length,
          message: '已导入 ${result.tracks.length} 首歌曲',
          label: result.sourceLabel,
        );
      });

  Future<void> rescanAll() =>
      _run(LibraryScanOperation.rescan, '全部搜索位置', () async {
        final sources = await _database.watchScanSources().first;
        if (sources.isEmpty) {
          return (count: 0, message: '还没有添加搜索位置', label: '全部搜索位置');
        }
        var imported = 0;
        for (final source in sources) {
          _message = '正在扫描：${source.label}';
          _publish();
          final result = await _scanner.rescanSource(
            sourceUri: source.uri,
            platform: source.platform,
            sourceLabel: source.label,
            fingerprintCache: await _database.fingerprintsForScanSource(source),
          );
          if (result == null) continue;
          await _database.transaction(() async {
            await _database.replaceScanSourceTracks(
              source,
              result.tracks.map(_toCompanion),
            );
            await _saveSource(result, previous: source);
          });
          imported += result.tracks.length;
        }
        return (
          count: imported,
          message: '已重新扫描 ${sources.length} 个位置，更新 $imported 首歌曲',
          label: '全部 ${sources.length} 个位置',
        );
      });

  Future<void> deleteSource(ScanSource source) =>
      _run(LibraryScanOperation.delete, source.label, () async {
        await _database.deleteScanSource(source);
        return (
          count: 0,
          message: '已删除搜索位置“${source.label}”并更新音乐库',
          label: source.label,
        );
      });

  Future<void> _saveSource(ScanResult result, {ScanSource? previous}) =>
      _database.saveScanSource(
        ScanSourcesCompanion.insert(
          id:
              previous?.id ??
              const Uuid().v5(Namespace.url.value, result.sourceUri),
          platform:
              result.tracks.firstOrNull?.sourceType ??
              previous?.platform ??
              'unknown',
          uri: result.sourceUri,
          label: result.sourceLabel,
          lastScannedAt: Value(DateTime.now()),
        ),
      );

  Future<void> _run(
    LibraryScanOperation next,
    String label,
    Future<({int count, String message, String label})?> Function() action,
  ) async {
    // Acquire before the first await so every page shares the same exclusion.
    if (busy) return;
    _operation = next;
    _hasError = false;
    _message = next == LibraryScanOperation.delete
        ? '正在删除搜索位置…'
        : '正在扫描：$label';
    _publish();
    var notify = false;
    try {
      notify =
          next != LibraryScanOperation.delete &&
          await _database.readSetting(scanNotificationEnabledSettingKey) !=
              'false';
      if (notify) {
        await _notify(
          () => _notifications.notifyScanStarted(
            sourceLabel: label,
            isRescan: next == LibraryScanOperation.rescan,
          ),
        );
      }
      final result = await action();
      _message = result?.message ?? '已取消扫描';
      if (notify) {
        await _notify(
          () => result == null
              ? _notifications.cancelScanNotification()
              : _notifications.notifyScanCompleted(
                  sourceLabel: result.label,
                  trackCount: result.count,
                  isRescan: next == LibraryScanOperation.rescan,
                ),
        );
      }
    } catch (error, stackTrace) {
      _hasError = true;
      _message =
          '${next == LibraryScanOperation.delete ? '删除搜索位置' : '扫描'}失败：$error';
      AppLog.error('音乐库操作失败', error, stackTrace);
      if (notify) {
        await _notify(
          () => _notifications.notifyScanFailed(
            sourceLabel: label,
            errorMessage: error.toString(),
          ),
        );
      }
    } finally {
      _operation = null;
      _publish();
    }
  }

  Future<void> _notify(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      AppLog.warning('扫描通知失败', error, stackTrace);
    }
  }

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

TracksCompanion _toCompanion(ScannedTrack track) => TracksCompanion.insert(
  id: track.id,
  sourceType: track.sourceType,
  sourceId: track.sourceId,
  uri: track.uri,
  filePath: Value(track.filePath),
  title: track.title,
  artist: Value(track.artist),
  album: Value(track.album),
  durationMs: Value(track.durationMs),
  artwork: Value(track.artwork),
  lyrics: Value(track.lyrics),
  fileSize: Value(track.fileSize),
  modifiedAt: Value(track.modifiedAt),
  contentFingerprint: Value(track.contentFingerprint),
  updatedAt: DateTime.now(),
);
