import 'scanned_track.dart';

abstract interface class LibraryScanner {
  bool get isSupported;
  String get actionLabel;
  Future<ScanResult?> scan();
}
