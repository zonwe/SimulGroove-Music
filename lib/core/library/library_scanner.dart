import 'scanned_track.dart';

abstract interface class LibraryScanner {
  bool get isSupported;
  bool get supportsFullDeviceScan;
  String get actionLabel;
  Future<ScanResult?> scan();
  Future<ScanResult?> scanFullDevice();
  Future<ScanResult?> rescanSource({
    required String sourceUri,
    required String platform,
    required String sourceLabel,
  });
}
