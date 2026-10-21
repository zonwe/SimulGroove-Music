/// 应用版本号：`1.2.3+4` 中的语义版本部分与 Flutter 构建号。
///
/// 发布清单把版本号与构建号分开存放，而 pubspec 和 Windows 版本资源使用
/// `version+build` 形式；这里统一成一个可比较、可序列化的模型，避免更新检查、
/// 设置页展示和“跳过此版本”各自实现一套解析。
class AppVersion implements Comparable<AppVersion> {
  const AppVersion._(this.parts, this.buildNumber);

  static final RegExp _pattern = RegExp(r'^(\d+(?:\.\d+){0,3})(?:\+(\d+))?$');

  /// 逐段版本号，例如 `[1, 2, 3]`。
  final List<int> parts;

  /// Flutter 构建号；缺失时为 0。
  final int buildNumber;

  factory AppVersion.parse(String raw) {
    final match = _pattern.firstMatch(raw.trim());
    if (match == null) {
      throw FormatException('无效的版本号：$raw');
    }
    final segments = match
        .group(1)!
        .split('.')
        .map(int.parse)
        .toList(growable: false);
    final buildText = match.group(2);
    final buildNumber = buildText == null ? 0 : int.parse(buildText);
    return AppVersion._(List<int>.unmodifiable(segments), buildNumber);
  }

  /// 兼容 `PackageInfo.version` 与可选的 `buildNumber`。
  ///
  /// 部分平台的 `PackageInfo.version` 已经包含 `+build`，此时不再拼接，
  /// 否则会得到非法的 `1.0.0+3+4`。
  factory AppVersion.fromPackageInfoVersion(
    String version, {
    String? buildNumber,
  }) {
    final normalized = version.trim();
    if (normalized.contains('+')) return AppVersion.parse(normalized);
    final build = (buildNumber ?? '').trim();
    return AppVersion.parse(build.isEmpty ? normalized : '$normalized+$build');
  }

  static AppVersion? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return AppVersion.parse(raw);
    } on FormatException {
      return null;
    }
  }

  /// 不含构建号的版本文本，例如 `1.2.3`。
  String get versionText => parts.join('.');

  /// 稳定序列化形式，用于“跳过此版本”等持久化比较。
  String get canonical => '$versionText+$buildNumber';

  /// 面向用户的展示文本，例如 `1.2.3（构建 4）`。
  String get display =>
      buildNumber == 0 ? versionText : '$versionText（构建 $buildNumber）';

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  int compareTo(AppVersion other) {
    final length = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (var index = 0; index < length; index++) {
      final left = index < parts.length ? parts[index] : 0;
      final right = index < other.parts.length ? other.parts[index] : 0;
      if (left != right) return left.compareTo(right);
    }
    return buildNumber.compareTo(other.buildNumber);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(_withoutTrailingZeros()), buildNumber);

  /// `1.1` 与 `1.1.0` 视为同一版本；忽略末尾的补零段。
  List<int> _withoutTrailingZeros() {
    var end = parts.length;
    while (end > 1 && parts[end - 1] == 0) {
      end--;
    }
    return parts.sublist(0, end);
  }

  @override
  String toString() => canonical;
}
