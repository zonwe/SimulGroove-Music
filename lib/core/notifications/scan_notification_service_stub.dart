import 'scan_notification_service.dart';

ScanNotificationService createScanNotificationService() =>
    const _StubScanNotificationService();

class _StubScanNotificationService implements ScanNotificationService {
  const _StubScanNotificationService();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> notifyScanStarted({
    required String sourceLabel,
    bool isRescan = false,
  }) async {}

  @override
  Future<void> notifyScanCompleted({
    required String sourceLabel,
    required int trackCount,
    bool isRescan = false,
  }) async {}

  @override
  Future<void> notifyScanFailed({
    required String sourceLabel,
    required String errorMessage,
  }) async {}

  @override
  Future<void> cancelScanNotification() async {}
}
