import 'library_scanner.dart';
import 'scanned_track.dart';

LibraryScanner createLibraryScanner() => const UnsupportedLibraryScanner();

class UnsupportedLibraryScanner implements LibraryScanner {
  const UnsupportedLibraryScanner();

  @override
  String get actionLabel => '当前平台暂不支持扫描';

  @override
  bool get isSupported => false;

  @override
  bool get supportsFullDeviceScan => false;

  @override
  Future<ScanResult?> scan() async => null;

  @override
  Future<ScanResult?> scanFullDevice() async => null;

  @override
  Future<ScanResult?> rescanSource({
    required String sourceUri,
    required String platform,
    required String sourceLabel,
  }) async => null;
}
