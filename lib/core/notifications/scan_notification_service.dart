abstract interface class ScanNotificationService {
  Future<void> initialize();

  Future<void> notifyScanStarted({
    required String sourceLabel,
    bool isRescan = false,
  });

  Future<void> notifyScanCompleted({
    required String sourceLabel,
    required int trackCount,
    bool isRescan = false,
  });

  Future<void> notifyScanFailed({
    required String sourceLabel,
    required String errorMessage,
  });

  Future<void> cancelScanNotification();
}
