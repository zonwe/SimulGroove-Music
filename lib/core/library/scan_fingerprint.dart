class ScanFingerprint {
  const ScanFingerprint({
    required this.path,
    required this.fileSize,
    required this.modifiedAt,
    required this.fingerprint,
  });

  final String path;
  final int fileSize;
  final DateTime modifiedAt;
  final String fingerprint;

  bool matches(int size, DateTime modified) =>
      fileSize == size &&
      // Drift stores existing modification timestamps with second precision.
      modifiedAt.millisecondsSinceEpoch ~/ 1000 ==
          modified.millisecondsSinceEpoch ~/ 1000;
}
