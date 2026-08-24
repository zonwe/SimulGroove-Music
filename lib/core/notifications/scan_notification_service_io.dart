import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:permission_handler/permission_handler.dart';

import 'scan_notification_service.dart';

ScanNotificationService createScanNotificationService() =>
    IoScanNotificationService();

class IoScanNotificationService implements ScanNotificationService {
  static const MethodChannel _channel = MethodChannel(
    'top.zonwe.simul_groove_player/media_store',
  );

  bool _initialized = false;
  LocalNotification? _desktopNotification;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await localNotifier.setup(
          appName: 'SimulGroove Music',
          shortcutPolicy: ShortcutPolicy.requireCreate,
        );
      }
      _initialized = true;
    } catch (e) {
      debugPrint('Failed to initialize local notifier: $e');
    }
  }

  @override
  Future<void> notifyScanStarted({
    required String sourceLabel,
    bool isRescan = false,
  }) async {
    final title = isRescan ? '正在重新扫描音乐库' : '正在扫描音乐库';
    final message = isRescan ? '正在重新扫描：$sourceLabel…' : '正在扫描：$sourceLabel…';

    if (Platform.isAndroid) {
      try {
        final permission = await Permission.notification.request();
        if (!permission.isGranted) return;
        await _channel.invokeMethod('showScanNotification', {
          'title': title,
          'message': message,
          'isOngoing': true,
          'indeterminate': true,
          'notificationId': 1001,
        });
      } catch (e) {
        debugPrint('Android scan start notification error: $e');
      }
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await _showDesktopNotification(title: title, message: message);
      } catch (e) {
        debugPrint('Desktop scan start notification error: $e');
      }
    }
  }

  @override
  Future<void> notifyScanCompleted({
    required String sourceLabel,
    required int trackCount,
    bool isRescan = false,
  }) async {
    final title = '音乐库扫描完成';
    final message = isRescan
        ? '已重新扫描“$sourceLabel”，共更新 $trackCount 首歌曲'
        : '已完成“$sourceLabel”扫描，共导入 $trackCount 首歌曲';

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('showScanNotification', {
          'title': title,
          'message': message,
          'isOngoing': false,
          'indeterminate': false,
          'notificationId': 1001,
        });
      } catch (e) {
        debugPrint('Android scan completed notification error: $e');
      }
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await _showDesktopNotification(title: title, message: message);
      } catch (e) {
        debugPrint('Desktop scan completed notification error: $e');
      }
    }
  }

  @override
  Future<void> notifyScanFailed({
    required String sourceLabel,
    required String errorMessage,
  }) async {
    final title = '音乐库扫描失败';
    final message = '扫描“$sourceLabel”失败：$errorMessage';

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('showScanNotification', {
          'title': title,
          'message': message,
          'isOngoing': false,
          'indeterminate': false,
          'notificationId': 1001,
        });
      } catch (e) {
        debugPrint('Android scan failed notification error: $e');
      }
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await _showDesktopNotification(title: title, message: message);
      } catch (e) {
        debugPrint('Desktop scan failed notification error: $e');
      }
    }
  }

  @override
  Future<void> cancelScanNotification() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('cancelScanNotification', {
          'notificationId': 1001,
        });
      } catch (e) {
        debugPrint('Android cancel scan notification error: $e');
      }
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await _desktopNotification?.destroy();
        _desktopNotification = null;
      } catch (e) {
        debugPrint('Desktop cancel scan notification error: $e');
      }
    }
  }

  Future<void> _showDesktopNotification({
    required String title,
    required String message,
  }) async {
    if (!_initialized) await initialize();
    await _desktopNotification?.destroy();
    final notification = LocalNotification(title: title, body: message);
    _desktopNotification = notification;
    await notification.show();
  }
}
