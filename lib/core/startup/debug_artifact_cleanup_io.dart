import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Future<void> cleanupObsoleteDebugArtifacts() async {
  if (!kReleaseMode || !Platform.isAndroid) return;

  try {
    final documents = await getApplicationDocumentsDirectory();
    final extractedAssets = Directory(
      path.join(documents.path, 'flutter_assets'),
    );
    final debugKernel = File(
      path.join(extractedAssets.path, 'kernel_blob.bin'),
    );
    if (!await debugKernel.exists()) return;

    await extractedAssets.delete(recursive: true);
    await for (final entry in documents.list(followLinks: false)) {
      if (entry is File &&
          path.basename(entry.path).startsWith('res_timestamp-')) {
        await entry.delete();
      }
    }

    final extractedEngine = Directory(
      path.join(documents.parent.path, 'app_lib'),
    );
    if (await extractedEngine.exists()) {
      await extractedEngine.delete(recursive: true);
    }
  } catch (_) {
    // Cleanup is best-effort and must never block launching or playback.
  }
}
