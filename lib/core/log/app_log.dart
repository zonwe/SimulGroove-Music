import 'package:flutter/foundation.dart';

/// 应用日志级别。
enum AppLogLevel { debug, warning, error }

/// 轻量应用日志：`debugPrint` 封装 + 级别前缀。
///
/// 项目暂不引入完整观测平台；此模块只保证"失败不应完全静默"，
/// 供启动配置、平台通知等有降级语义的路径记录上下文。
/// 注意：日志会进入控制台/logcat，禁止输出令牌、密码等敏感数据。
class AppLog {
  AppLog._();

  static void debug(String message, [Object? error, StackTrace? stackTrace]) =>
      _write(AppLogLevel.debug, message, error, stackTrace);

  static void warning(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => _write(AppLogLevel.warning, message, error, stackTrace);

  static void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _write(AppLogLevel.error, message, error, stackTrace);

  static void _write(
    AppLogLevel level,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    debugPrint(
      '[app/${level.name}] $message'
      '${error == null ? '' : '\n  error: $error'}'
      '${stackTrace == null ? '' : '\n$stackTrace'}',
    );
  }
}
