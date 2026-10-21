import 'app_version.dart';
import 'update_manifest.dart';
import 'update_service.dart';

AppUpdateService createAppUpdateService() =>
    const UnsupportedAppUpdateService();

/// Web 等没有 `dart:io` 的平台使用空实现，保证条件导出可编译。
class UnsupportedAppUpdateService implements AppUpdateService {
  const UnsupportedAppUpdateService();

  @override
  bool get isSupported => false;

  @override
  bool get isInstalled => false;

  @override
  String get platformLabel => '当前平台';

  @override
  bool get requiresAppExit => false;

  @override
  String get installHint => '当前平台暂不支持应用内更新。';

  @override
  Future<AppVersion> currentVersion() async => AppVersion.parse('0.0.0');

  @override
  Future<UpdateCheckResult> checkForUpdates() async =>
      const UpdateUnsupported('当前平台暂不支持应用内更新。');

  @override
  Future<String> downloadUpdate(
    UpdateAsset asset, {
    UpdateProgressCallback? onProgress,
  }) async =>
      throw const UpdateException('当前平台暂不支持应用内更新。', code: 'update_unsupported');

  @override
  Future<void> launchInstaller({
    required String installerPath,
    required AppVersion targetVersion,
  }) async =>
      throw const UpdateException('当前平台暂不支持自动安装。', code: 'update_unsupported');

  @override
  Future<String?> takePendingFailure() async => null;

  @override
  Future<void> dispose() async {}
}
