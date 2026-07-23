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
  Future<ScanResult?> scan() async => null;
}
