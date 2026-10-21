/// 生成 Windows 更新助手脚本（纯字符串，便于单元测试）。
///
/// 为什么需要助手脚本：Flutter 进程无法在退出后继续替换自身。更新器只负责
/// 下载并校验安装包，真正的“等待旧进程退出 → 静默运行安装器 → 重新启动”
/// 交给一个独立于本进程的 cmd 脚本，避免托盘/窗口生命周期干扰安装。
///
/// 路径不写入脚本，而是通过环境变量传给 `cmd.exe`：Windows 批处理文件按
/// 控制台代码页读取，直接把中文用户名路径写进脚本会被错误解码；环境变量
/// 走 Unicode 的 `CreateProcessW` 环境块，不受代码页影响。
library;

/// 助手脚本读取的环境变量名。
const updateHelperInstallerEnv = 'SIMULGROOVE_UPDATE_INSTALLER';
const updateHelperExecutableEnv = 'SIMULGROOVE_UPDATE_EXE';
const updateHelperLogEnv = 'SIMULGROOVE_UPDATE_LOG';
const updateHelperStartedEnv = 'SIMULGROOVE_UPDATE_STARTED';
const updateHelperFailedEnv = 'SIMULGROOVE_UPDATE_FAILED';
const updateHelperImageNameEnv = 'SIMULGROOVE_UPDATE_IMAGE_NAME';

String buildUpdateHelperScript({
  required int processId,
  Duration waitTimeout = const Duration(minutes: 3),
}) {
  if (processId <= 0) {
    throw ArgumentError.value(processId, 'processId', '必须是有效的进程号');
  }
  final waitAttempts = waitTimeout.inSeconds.clamp(10, 600);

  return <String>[
    '@echo off',
    'setlocal DisableDelayedExpansion',
    'set "UPDATE_PROCESS_ID=$processId"',
    'set "UPDATE_WAIT_ATTEMPTS=$waitAttempts"',
    'if not defined $updateHelperInstallerEnv goto environment_error',
    'if not defined $updateHelperExecutableEnv goto environment_error',
    'if not defined $updateHelperLogEnv goto environment_error',
    'if not defined $updateHelperStartedEnv goto environment_error',
    'if not defined $updateHelperFailedEnv goto environment_error',
    'if not defined $updateHelperImageNameEnv goto environment_error',
    'echo started>"%$updateHelperStartedEnv%"',
    'set /a UPDATE_WAIT_COUNT=0',
    ':wait_for_exit',
    'tasklist /FI "PID eq %UPDATE_PROCESS_ID%" /NH 2>nul | find /I "%$updateHelperImageNameEnv%" >nul',
    'if errorlevel 1 goto run_installer',
    'set /a UPDATE_WAIT_COUNT+=1',
    'if %UPDATE_WAIT_COUNT% GEQ %UPDATE_WAIT_ATTEMPTS% goto run_installer',
    // 助手由 DETACHED_PROCESS 启动时可能没有控制台，timeout 会立即失败并让
    // 等待循环空转；ping 本机不依赖控制台，可作为约 1 秒的延时。
    'ping -n 2 127.0.0.1 >nul 2>&1',
    'goto wait_for_exit',
    ':run_installer',
    'start "" /wait "%$updateHelperInstallerEnv%" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /FORCECLOSEAPPLICATIONS /LOG="%$updateHelperLogEnv%"',
    'set "UPDATE_EXIT_CODE=%ERRORLEVEL%"',
    'if not "%UPDATE_EXIT_CODE%"=="0" goto install_failed',
    'del "%$updateHelperFailedEnv%" >nul 2>&1',
    'start "" "%$updateHelperExecutableEnv%"',
    'del "%$updateHelperInstallerEnv%" >nul 2>&1',
    'goto cleanup',
    ':install_failed',
    '> "%$updateHelperFailedEnv%" echo exit_code=%UPDATE_EXIT_CODE%',
    '>> "%$updateHelperFailedEnv%" echo log=%$updateHelperLogEnv%',
    'start "" "%$updateHelperExecutableEnv%"',
    'goto cleanup',
    ':environment_error',
    'exit /b 1',
    ':cleanup',
    '(goto) 2>nul & del "%~f0"',
    'exit /b 0',
    '',
  ].join('\r\n');
}

/// 校验会通过环境变量传给助手脚本的 Windows 路径。
///
/// 路径值不会被 cmd 再次解析变量，因此允许 `%`；但引号与换行会破坏命令
/// 参数分界，必须拒绝。
void validateWindowsUpdateHelperPath(
  String value, {
  required String name,
  String? extension,
}) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, '不能为空');
  }
  if (!_absoluteWindowsPath.hasMatch(value)) {
    throw ArgumentError.value(value, name, '必须是 Windows 绝对路径');
  }
  if (extension != null &&
      !value.toLowerCase().endsWith(extension.toLowerCase())) {
    throw ArgumentError.value(value, name, '必须以 $extension 结尾');
  }
  if (value.contains('"') ||
      value.contains('\r') ||
      value.contains('\n') ||
      value.contains('\u0000')) {
    throw ArgumentError.value(value, name, '包含命令参数不支持的字符');
  }
}

final RegExp _absoluteWindowsPath = RegExp(r'^[A-Za-z]:[\\/]|^\\\\');
