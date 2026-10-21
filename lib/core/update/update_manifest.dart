import 'app_version.dart';

/// 当前客户端理解的发布清单版本。
const int updateManifestSchemaVersion = 1;

/// 发布说明长度上限，避免异常清单撑爆设置页弹窗。
const int maxUpdateNotesLength = 20000;

/// 单个更新包大小上限，防止清单错误导致下载失控。
const int maxUpdateAssetSizeBytes = 1024 * 1024 * 1024;

const int maxUpdateAssetUrlLength = 2048;

const int maxUpdateManifestAssets = 8;

final RegExp _sha256Pattern = RegExp(r'^[a-fA-F0-9]{64}$');
// Android 的 ABI 标识包含下划线（android-x86_64），不能只允许连字符。
final RegExp _platformKeyPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');

/// 更新包类型。
///
/// - `installer`：Windows 安装器，可退出应用后静默升级。
/// - `apk`：Android 安装包，只能交给系统安装界面确认安装。
/// - `portableArchive`：压缩包，仅用于手工替换。
enum UpdateAssetKind { installer, apk, portableArchive }

class UpdateAsset {
  const UpdateAsset({
    required this.uri,
    required this.size,
    required this.sha256,
    required this.kind,
  });

  final Uri uri;
  final int size;

  /// 小写十六进制 SHA-256。
  final String sha256;
  final UpdateAssetKind kind;

  /// 从 URL 推导的下载文件名；只用于临时文件命名，最终以清单为重。
  String get suggestedFileName {
    final segments = uri.pathSegments;
    return segments.isEmpty ? 'update' : segments.last;
  }
}

class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.publishedAt,
    required this.notes,
    required this.assets,
  });

  final AppVersion version;
  final DateTime publishedAt;
  final String notes;
  final Map<String, UpdateAsset> assets;

  UpdateAsset? assetFor(String platformKey) => assets[platformKey];
}

class UpdateManifest {
  const UpdateManifest({
    required this.schemaVersion,
    required this.channel,
    required this.release,
  });

  final int schemaVersion;
  final String channel;
  final UpdateRelease release;
}

/// 解析并校验发布清单。
///
/// 这里只做与部署无关的格式校验（HTTPS、哈希、大小）；主机白名单由更新服务
/// 结合清单来源地址判断，避免把域名策略固化进模型。
UpdateManifest parseUpdateManifest(
  Object? json, {
  int expectedSchemaVersion = updateManifestSchemaVersion,
}) {
  final root = _requireMap(json, '更新清单');

  final schemaVersion = _requireInt(root, 'schemaVersion');
  if (schemaVersion != expectedSchemaVersion) {
    throw FormatException(
      '不支持的更新清单版本：$schemaVersion（期望 $expectedSchemaVersion）',
    );
  }

  final channel = _requireString(root, 'channel', maxLength: 32);
  final version = _parseVersion(root, 'version', 'buildNumber');
  final publishedAt = _parseDateTime(root, 'publishedAt');
  final notes = _optionalString(root, 'notes', maxLength: maxUpdateNotesLength);
  final assetsJson = _requireMap(root['assets'], 'assets');
  if (assetsJson.isEmpty) {
    throw const FormatException('更新清单没有提供任何平台的安装包。');
  }
  if (assetsJson.length > maxUpdateManifestAssets) {
    throw FormatException('更新清单包含过多平台条目（${assetsJson.length}）。');
  }

  final assets = <String, UpdateAsset>{};
  for (final entry in assetsJson.entries) {
    final key = entry.key;
    if (!_platformKeyPattern.hasMatch(key)) {
      throw FormatException('非法的平台标识：$key');
    }
    assets[key] = _parseAsset(entry.value, key);
  }

  return UpdateManifest(
    schemaVersion: schemaVersion,
    channel: channel,
    release: UpdateRelease(
      version: version,
      publishedAt: publishedAt,
      notes: notes ?? '',
      assets: Map<String, UpdateAsset>.unmodifiable(assets),
    ),
  );
}

AppVersion _parseVersion(
  Map<String, Object?> map,
  String versionKey,
  String buildNumberKey,
) {
  final versionText = _requireString(map, versionKey, maxLength: 64);
  final buildNumber = _requireInt(map, buildNumberKey);
  if (buildNumber < 0) {
    throw FormatException('$buildNumberKey 不能为负数。');
  }
  final parsed = AppVersion.tryParse(
    versionText.contains('+') ? versionText : '$versionText+$buildNumber',
  );
  if (parsed == null) {
    throw FormatException('更新清单中的版本号无效：$versionText');
  }
  if (parsed.buildNumber != buildNumber) {
    throw const FormatException('version 中的构建号与 buildNumber 不一致。');
  }
  return parsed;
}

DateTime _parseDateTime(Map<String, Object?> map, String key) {
  final text = _requireString(map, key, maxLength: 64);
  final parsed = DateTime.tryParse(text);
  if (parsed == null) {
    throw FormatException('$key 不是有效的 ISO-8601 时间：$text');
  }
  return parsed.toUtc();
}

UpdateAsset _parseAsset(Object? value, String platformKey) {
  final map = _requireMap(value, 'assets.$platformKey');
  final urlText = _requireString(
    map,
    'url',
    maxLength: maxUpdateAssetUrlLength,
  );
  final uri = Uri.tryParse(urlText);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
    throw FormatException('assets.$platformKey.url 不是有效地址。');
  }
  if (uri.scheme != 'https') {
    throw FormatException('assets.$platformKey.url 必须使用 HTTPS。');
  }
  if (uri.userInfo.isNotEmpty) {
    throw FormatException('assets.$platformKey.url 不允许包含凭据。');
  }

  final size = _requireInt(map, 'size');
  if (size <= 0 || size > maxUpdateAssetSizeBytes) {
    throw FormatException('assets.$platformKey.size 超出允许范围：$size');
  }

  final sha256 = _requireString(map, 'sha256', maxLength: 64).toLowerCase();
  if (!_sha256Pattern.hasMatch(sha256)) {
    throw FormatException('assets.$platformKey.sha256 不是 64 位十六进制摘要。');
  }

  final kindText = _requireString(map, 'kind', maxLength: 32);
  final kind = switch (kindText) {
    'installer' => UpdateAssetKind.installer,
    'apk' => UpdateAssetKind.apk,
    'portable' => UpdateAssetKind.portableArchive,
    _ => throw FormatException('assets.$platformKey.kind 不受支持：$kindText'),
  };

  return UpdateAsset(uri: uri, size: size, sha256: sha256, kind: kind);
}

Map<String, Object?> _requireMap(Object? value, String label) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('$label 的键必须是字符串。');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
  throw FormatException('$label 必须是对象。');
}

String _requireString(
  Map<String, Object?> map,
  String key, {
  required int maxLength,
}) {
  final value = map[key];
  if (value is! String) {
    throw FormatException('$key 必须是字符串。');
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw FormatException('$key 不能为空。');
  }
  if (trimmed.length > maxLength) {
    throw FormatException('$key 超过长度上限（$maxLength）。');
  }
  return trimmed;
}

String? _optionalString(
  Map<String, Object?> map,
  String key, {
  required int maxLength,
}) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$key 必须是字符串。');
  }
  if (value.length > maxLength) {
    throw FormatException('$key 超过长度上限（$maxLength）。');
  }
  return value;
}

int _requireInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) {
    throw FormatException('$key 必须是整数。');
  }
  return value;
}
