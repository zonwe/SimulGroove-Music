import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../log/app_log.dart';
import 'app_version.dart';
import 'update_install_script.dart';
import 'update_manifest.dart';
import 'update_service.dart';

/// 默认更新清单地址。
///
/// GitHub `releases/latest/download/<asset>` 是稳定地址，会重定向到最新正式
/// 版本；自建分发时可以用 `--dart-define=UPDATE_MANIFEST_URL=...` 覆盖。
const defaultUpdateManifestUrl = String.fromEnvironment(
  'UPDATE_MANIFEST_URL',
  defaultValue:
      'https://github.com/zonwe/SimulGroove-Music/releases/latest/download/latest.json',
);

const _trustedUpdateHosts = <String>{
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

const _manifestTimeout = Duration(seconds: 20);
const _downloadInactivityTimeout = Duration(seconds: 60);
const _helperStartTimeout = Duration(seconds: 5);

const _androidUpdaterChannel = MethodChannel(
  'top.zonwe.simul_groove_player/updater',
);

AppUpdateService createAppUpdateService() => DesktopAppUpdateService();

class DesktopAppUpdateService implements AppUpdateService {
  DesktopAppUpdateService({
    http.Client? client,
    Uri? manifestUri,
    this.readInstalledVersion,
    Future<Directory> Function()? temporaryDirectory,
    String? executablePath,
    this.windowsOverride,
    this.platformKeyOverride,
    this.installedOverride,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _manifestUri = manifestUri ?? Uri.parse(defaultUpdateManifestUrl),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _executablePath = executablePath ?? Platform.resolvedExecutable;

  /// 可替换的版本读取器，便于测试或嵌入其他宿主。
  final Future<String> Function()? readInstalledVersion;

  /// 测试/嵌入时可覆盖平台判断，避免测试依赖真实操作系统。
  final bool? windowsOverride;
  final String? platformKeyOverride;
  final bool? installedOverride;

  final http.Client _client;
  final bool _ownsClient;
  final Uri _manifestUri;
  final Future<Directory> Function() _temporaryDirectory;
  final String _executablePath;
  AppVersion? _cachedVersion;
  bool _downloadInProgress = false;

  @override
  bool get isSupported =>
      (windowsOverride ?? Platform.isWindows) || Platform.isAndroid;

  @override
  bool get isInstalled {
    final override = installedOverride;
    if (override != null) return override;
    if (Platform.isAndroid) return true;
    if (!Platform.isWindows) return false;
    final uninstaller = File(
      p.join(File(_executablePath).parent.path, 'unins000.exe'),
    );
    return uninstaller.existsSync();
  }

  @override
  String get platformLabel => switch (_platformKey) {
    'windows-x64' => 'Windows x64',
    'windows-arm64' => 'Windows ARM64',
    'android-arm64-v8a' => 'Android arm64-v8a',
    'android-armeabi-v7a' => 'Android armeabi-v7a',
    'android-x86_64' => 'Android x86_64',
    'android-x86' => 'Android x86',
    _ => Platform.operatingSystem,
  };

  @override
  bool get requiresAppExit => windowsOverride ?? Platform.isWindows;

  @override
  String get installHint => requiresAppExit
      ? '应用会退出，安装器将在后台完成升级并重新启动。'
      : '将打开系统安装界面，请确认安装；系统会校验签名并替换当前版本。';

  String get _platformKey {
    final override = platformKeyOverride;
    if (override != null) return override;
    if (Platform.isWindows) {
      return Abi.current() == Abi.windowsArm64
          ? 'windows-arm64'
          : 'windows-x64';
    }
    if (Platform.isAndroid) {
      return switch (Abi.current()) {
        Abi.androidArm64 => 'android-arm64-v8a',
        Abi.androidArm => 'android-armeabi-v7a',
        Abi.androidX64 => 'android-x86_64',
        Abi.androidIA32 => 'android-x86',
        _ => 'android-arm64-v8a',
      };
    }
    return 'unsupported';
  }

  UpdateAssetKind get _expectedAssetKind =>
      Platform.isAndroid ? UpdateAssetKind.apk : UpdateAssetKind.installer;

  @override
  Future<AppVersion> currentVersion() async {
    final cached = _cachedVersion;
    if (cached != null) return cached;
    try {
      final raw = await _readVersionText();
      final version = AppVersion.tryParse(raw);
      if (version == null) {
        throw FormatException('无法解析版本号：$raw');
      }
      _cachedVersion = version;
      return version;
    } on UpdateException {
      rethrow;
    } catch (error) {
      throw UpdateException(
        '无法读取当前应用版本：$error',
        code: 'update_version_unavailable',
      );
    }
  }

  Future<String> _readVersionText() async {
    final loader = readInstalledVersion;
    if (loader != null) return loader();
    final info = await PackageInfo.fromPlatform();
    return AppVersion.fromPackageInfoVersion(
      info.version,
      buildNumber: info.buildNumber,
    ).canonical;
  }

  @override
  Future<UpdateCheckResult> checkForUpdates() async {
    if (!isSupported) {
      return const UpdateUnsupported('当前平台暂不支持应用内更新。');
    }
    final current = await currentVersion();
    final manifest = await _fetchManifest();
    final release = manifest.release;
    if (!release.version.isNewerThan(current)) {
      return UpdateUpToDate(current: current, latest: release.version);
    }
    final asset = release.assetFor(_platformKey);
    if (asset == null) {
      throw UpdateException(
        '新版本没有提供 $platformLabel 安装包。',
        code: 'update_asset_missing',
      );
    }
    _validateAssetUri(asset.uri);
    return UpdateAvailable(current: current, release: release, asset: asset);
  }

  Future<UpdateManifest> _fetchManifest() async {
    if (_manifestUri.scheme != 'https') {
      throw const UpdateException(
        '更新源必须使用 HTTPS。',
        code: 'update_manifest_insecure',
      );
    }
    final request = http.Request('GET', _manifestUri)
      ..headers['Accept'] = 'application/json'
      ..headers['User-Agent'] = 'SimulGrooveMusic';
    final response = await _send(request);
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw UpdateException(
        _manifestStatusMessage(response.statusCode),
        code: 'update_manifest_http_${response.statusCode}',
      );
    }
    final declaredLength = response.contentLength;
    if (declaredLength != null && declaredLength > _maxManifestBytes) {
      await response.stream.drain<void>();
      throw const UpdateException(
        '更新清单过大，已拒绝解析。',
        code: 'update_manifest_too_large',
      );
    }

    final String body;
    try {
      body = await response.stream.bytesToString().timeout(_manifestTimeout);
    } on TimeoutException {
      throw const UpdateException(
        '读取更新清单超时，请稍后重试。',
        code: 'update_manifest_timeout',
      );
    }
    if (body.length > _maxManifestBytes) {
      throw const UpdateException(
        '更新清单过大，已拒绝解析。',
        code: 'update_manifest_too_large',
      );
    }

    try {
      return parseUpdateManifest(jsonDecode(body));
    } on FormatException catch (error) {
      throw UpdateException(
        '更新清单格式无效：${error.message}',
        code: 'update_manifest_invalid',
      );
    }
  }

  static const int _maxManifestBytes = 256 * 1024;

  String _manifestStatusMessage(int statusCode) => switch (statusCode) {
    404 => '更新源暂时没有发布清单，请稍后再试。',
    403 || 429 => '更新源拒绝了请求（HTTP $statusCode），请稍后再试。',
    _ => '检查更新失败（HTTP $statusCode）。',
  };

  Future<http.StreamedResponse> _send(http.BaseRequest request) async {
    try {
      return await _client.send(request).timeout(_manifestTimeout);
    } on TimeoutException {
      throw const UpdateException(
        '连接更新服务器超时，请检查网络。',
        code: 'update_network_timeout',
      );
    } on http.ClientException catch (error) {
      throw UpdateException(
        '无法连接更新服务器：${error.message}',
        code: 'update_network',
      );
    } on IOException catch (error) {
      throw UpdateException('无法连接更新服务器：$error', code: 'update_network');
    }
  }

  @override
  Future<String> downloadUpdate(
    UpdateAsset asset, {
    UpdateProgressCallback? onProgress,
  }) async {
    // 启动自动下载与设置页手动下载可能同时发生；串行化可避免两个写入者
    // 争用同一个 .part 文件。
    if (_downloadInProgress) {
      throw const UpdateException(
        '已有更新包正在下载，请稍后再试。',
        code: 'update_download_busy',
      );
    }
    _downloadInProgress = true;
    try {
      return await _downloadUpdate(asset, onProgress: onProgress);
    } finally {
      _downloadInProgress = false;
    }
  }

  Future<String> _downloadUpdate(
    UpdateAsset asset, {
    UpdateProgressCallback? onProgress,
  }) async {
    if (asset.kind != _expectedAssetKind) {
      throw const UpdateException(
        '更新包类型与当前平台不匹配，无法安装。',
        code: 'update_asset_kind',
      );
    }
    _validateAssetUri(asset.uri);
    final directory = await _updateDirectory();
    final target = File(
      p.join(directory.path, _safeFileName(asset.suggestedFileName)),
    );
    if (await _matchesExisting(target, asset)) return target.path;

    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();

    http.StreamedResponse? response;
    try {
      final request = http.Request('GET', asset.uri)
        ..headers['Accept'] = 'application/octet-stream'
        ..headers['User-Agent'] = 'SimulGrooveMusic';
      response = await _send(request);
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw UpdateException(
          '下载更新包失败（HTTP ${response.statusCode}）。',
          code: 'update_download_http_${response.statusCode}',
        );
      }
      final declaredLength = response.contentLength;
      if (declaredLength != null && declaredLength != asset.size) {
        await response.stream.drain<void>();
        throw const UpdateException(
          '更新包大小与发布清单不一致，已中止下载。',
          code: 'update_download_size_mismatch',
        );
      }

      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(
          _downloadInactivityTimeout,
        )) {
          received += chunk.length;
          if (received > asset.size) {
            throw const UpdateException(
              '下载内容超过发布清单声明的大小，已中止。',
              code: 'update_download_oversize',
            );
          }
          sink.add(chunk);
          onProgress?.call(received, asset.size);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (received != asset.size) {
        throw UpdateException(
          '更新包下载不完整（$received / ${asset.size} 字节）。',
          code: 'update_download_incomplete',
        );
      }
      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString().toLowerCase() != asset.sha256) {
        throw const UpdateException(
          '更新包 SHA-256 校验失败，已丢弃下载内容。',
          code: 'update_checksum_mismatch',
        );
      }
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
      return target.path;
    } on TimeoutException {
      throw const UpdateException(
        '下载更新包超时，请检查网络后重试。',
        code: 'update_download_timeout',
      );
    } on UpdateException {
      await _deleteIfExists(partial);
      rethrow;
    } on IOException catch (error) {
      await _deleteIfExists(partial);
      throw UpdateException('下载更新包失败：$error', code: 'update_download_io');
    } finally {
      // 正常完成时 partial 已改名；异常路径在 catch 中已删除。
      await _deleteIfExists(partial);
    }
  }

  Future<bool> _matchesExisting(File file, UpdateAsset asset) async {
    if (!await file.exists()) return false;
    if (await file.length() != asset.size) return false;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == asset.sha256;
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 清理失败不影响主流程；临时目录最终由系统回收。
    }
  }

  String _safeFileName(String raw) {
    final base = p.basename(raw);
    final cleaned = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final fallback = Platform.isAndroid
        ? 'SimulGrooveMusic-update.apk'
        : 'SimulGrooveMusic-update.exe';
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return fallback;
    final limited = cleaned.length > 120
        ? cleaned.substring(cleaned.length - 120)
        : cleaned;
    final extension = Platform.isAndroid ? '.apk' : '.exe';
    return limited.toLowerCase().endsWith(extension)
        ? limited
        : '$limited$extension';
  }

  @override
  Future<void> launchInstaller({
    required String installerPath,
    required AppVersion targetVersion,
  }) async {
    if (!isSupported) {
      throw const UpdateException(
        '当前平台暂不支持自动安装。',
        code: 'update_install_unsupported',
      );
    }
    final installer = File(installerPath);
    if (!await installer.exists()) {
      throw const UpdateException(
        '更新包已不存在，请重新下载。',
        code: 'update_installer_missing',
      );
    }
    if (Platform.isAndroid) {
      if (!installerPath.toLowerCase().endsWith('.apk')) {
        throw const UpdateException(
          '更新包不是 Android 安装包，无法安装。',
          code: 'update_installer_type',
        );
      }
      await _installAndroidApk(installer);
      return;
    }
    if (!isInstalled) {
      throw const UpdateException(
        '当前是解压版，自动安装不可用。请下载安装包后手动安装。',
        code: 'update_not_installed',
      );
    }
    if (!installerPath.toLowerCase().endsWith('.exe')) {
      throw const UpdateException(
        '更新包不是 Windows 安装器，无法自动安装。',
        code: 'update_installer_type',
      );
    }
    if (!await File(_executablePath).exists()) {
      throw const UpdateException(
        '无法定位当前程序路径，请手动安装更新。',
        code: 'update_executable_missing',
      );
    }

    final directory = await _updateDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final helper = File(p.join(directory.path, 'apply-update-$stamp.cmd'));
    final startedMarker = File(
      p.join(directory.path, 'update-started-$stamp.txt'),
    );
    final log = File(p.join(directory.path, 'update-install-$stamp.log'));
    final failedMarker = File(p.join(directory.path, 'update-failed.txt'));

    await _deleteIfExists(startedMarker);
    try {
      validateWindowsUpdateHelperPath(
        installer.path,
        name: 'installerPath',
        extension: '.exe',
      );
      validateWindowsUpdateHelperPath(
        _executablePath,
        name: 'executablePath',
        extension: '.exe',
      );
      validateWindowsUpdateHelperPath(log.path, name: 'logPath');
      validateWindowsUpdateHelperPath(
        startedMarker.path,
        name: 'startedMarkerPath',
      );
      validateWindowsUpdateHelperPath(
        failedMarker.path,
        name: 'failedMarkerPath',
      );
    } on ArgumentError catch (error) {
      throw UpdateException(
        '更新路径无效：${error.message}',
        code: 'update_helper_path_invalid',
      );
    }

    final script = buildUpdateHelperScript(processId: pid);
    try {
      await helper.writeAsString(script, flush: true);
      await Process.start(
        'cmd.exe',
        ['/c', 'start', '', '/b', helper.path],
        mode: ProcessStartMode.detached,
        environment: {
          updateHelperInstallerEnv: installer.path,
          updateHelperExecutableEnv: _executablePath,
          updateHelperLogEnv: log.path,
          updateHelperStartedEnv: startedMarker.path,
          updateHelperFailedEnv: failedMarker.path,
          updateHelperImageNameEnv: p.basename(_executablePath),
        },
      );
    } on ProcessException catch (error) {
      throw UpdateException(
        '无法启动更新助手：${error.message}',
        code: 'update_helper_failed',
      );
    } on FileSystemException catch (error) {
      throw UpdateException(
        '无法写入更新助手：$error',
        code: 'update_helper_write_failed',
      );
    }

    final deadline = DateTime.now().add(_helperStartTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await startedMarker.exists()) return;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw const UpdateException(
      '更新助手没有响应，应用将保持运行。请稍后重试或手动安装。',
      code: 'update_helper_unavailable',
    );
  }

  /// Android 不允许静默安装；通过 FileProvider 把缓存中的 APK 交给系统安装器。
  Future<void> _installAndroidApk(File apk) async {
    try {
      await _androidUpdaterChannel.invokeMethod<void>('installApk', {
        'path': apk.path,
      });
    } on PlatformException catch (error) {
      throw UpdateException(
        error.message ?? '无法打开 Android 安装界面。',
        code: error.code,
      );
    } on MissingPluginException {
      throw const UpdateException(
        '当前安装包缺少 Android 安装桥，无法自动安装。',
        code: 'update_android_bridge_missing',
      );
    }
  }

  @override
  Future<String?> takePendingFailure() async {
    // 失败标记只由 Windows 更新助手写入；Android 系统安装器会直接给出结果。
    if (!Platform.isWindows) return null;
    final directory = await _updateDirectory(create: false);
    final marker = File(p.join(directory.path, 'update-failed.txt'));
    if (!await marker.exists()) return null;
    try {
      final content = await marker.readAsString();
      await marker.delete();
      final trimmed = content.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (error) {
      AppLog.warning('读取更新失败标记失败', error);
      return null;
    }
  }

  Future<Directory> _updateDirectory({bool create = true}) async {
    final temp = await _temporaryDirectory();
    final directory = Directory(
      p.join(temp.path, 'SimulGrooveMusic', 'updates'),
    );
    if (create) await directory.create(recursive: true);
    return directory;
  }

  void _validateAssetUri(Uri uri) {
    if (uri.scheme != 'https') {
      throw const UpdateException(
        '更新包地址必须使用 HTTPS。',
        code: 'update_asset_insecure',
      );
    }
    final allowedHosts = {
      ..._trustedUpdateHosts,
      _manifestUri.host.toLowerCase(),
    };
    if (!allowedHosts.contains(uri.host.toLowerCase())) {
      throw UpdateException(
        '更新包地址不在受信任的主机列表内：${uri.host}',
        code: 'update_untrusted_host',
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_ownsClient) _client.close();
  }
}
