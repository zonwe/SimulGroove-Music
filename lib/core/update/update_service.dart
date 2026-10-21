import 'app_version.dart';
import 'update_manifest.dart';

/// 更新流程中的可预期错误，消息可以直接展示给用户。
class UpdateException implements Exception {
  const UpdateException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// 当前平台不支持应用内更新（Web、Linux、Android 或未打包运行）。
final class UpdateUnsupported extends UpdateCheckResult {
  const UpdateUnsupported(this.reason);

  final String reason;
}

final class UpdateUpToDate extends UpdateCheckResult {
  const UpdateUpToDate({required this.current, this.latest});

  final AppVersion current;
  final AppVersion? latest;
}

final class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable({
    required this.current,
    required this.release,
    required this.asset,
  });

  final AppVersion current;
  final UpdateRelease release;
  final UpdateAsset asset;
}

typedef UpdateProgressCallback = void Function(int received, int? total);

/// 应用内更新边界。
///
/// 检查、下载、校验与启动安装器都在核心层完成；页面只负责展示进度和
/// 在安装器准备好后按顺序退出应用。
abstract interface class AppUpdateService {
  /// 当前平台是否提供应用内更新。
  bool get isSupported;

  /// 是否由 Windows 安装器安装。解压版没有卸载器，不能静默覆盖自身。
  bool get isInstalled;

  /// 面向用户的平台名称，例如 `Windows x64`。
  String get platformLabel;

  /// 启动安装器前是否必须退出当前进程。
  ///
  /// Windows 需要先退出以释放 exe/DLL；Android 由系统安装界面接管，
  /// 不需要也不能主动退出。
  bool get requiresAppExit;

  /// 安装阶段的用户提示。
  String get installHint;

  Future<AppVersion> currentVersion();

  Future<UpdateCheckResult> checkForUpdates();

  /// 下载并校验更新包，返回本地文件路径。
  Future<String> downloadUpdate(
    UpdateAsset asset, {
    UpdateProgressCallback? onProgress,
  });

  /// 生成并启动更新助手；调用方随后必须退出应用。
  Future<void> launchInstaller({
    required String installerPath,
    required AppVersion targetVersion,
  });

  /// 读取并清除上一次静默安装留下的失败标记。
  Future<String?> takePendingFailure();

  Future<void> dispose();
}
