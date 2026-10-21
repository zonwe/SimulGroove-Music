import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_music/core/update/update_install_script.dart';

String _script({
  int processId = 4242,
  Duration waitTimeout = const Duration(minutes: 2),
}) => buildUpdateHelperScript(processId: processId, waitTimeout: waitTimeout);

void main() {
  test(
    'builds a helper that waits for the app and runs a silent installer',
    () {
      final script = _script();

      expect(script, startsWith('@echo off\r\n'));
      expect(script, contains('set "UPDATE_PROCESS_ID=4242"'));
      expect(script, contains('set "UPDATE_WAIT_ATTEMPTS=120"'));
      expect(script, contains('tasklist /FI "PID eq %UPDATE_PROCESS_ID%"'));
      // detached 进程可能没有控制台；不能用 timeout 作为等待。
      expect(script, contains('ping -n 2 127.0.0.1'));
      expect(script, isNot(contains('timeout /t')));
      expect(script, contains('/VERYSILENT'));
      expect(script, contains('/SUPPRESSMSGBOXES'));
      expect(script, contains('/LOG="%$updateHelperLogEnv%"'));
      expect(script, contains('start "" "%$updateHelperExecutableEnv%"'));
      expect(script, contains('echo started>"%$updateHelperStartedEnv%"'));
      expect(
        script,
        contains(
          '> "%$updateHelperFailedEnv%" echo exit_code=%UPDATE_EXIT_CODE%',
        ),
      );
      expect(
        script,
        contains(
          'if not defined $updateHelperInstallerEnv goto environment_error',
        ),
      );
      expect(script, contains('(goto) 2>nul & del "%~f0"'));
    },
  );

  test('clamps the wait timeout to a safe range', () {
    expect(
      _script(waitTimeout: const Duration(seconds: 1)),
      contains('set "UPDATE_WAIT_ATTEMPTS=10"'),
    );
    expect(
      _script(waitTimeout: const Duration(hours: 1)),
      contains('set "UPDATE_WAIT_ATTEMPTS=600"'),
    );
  });

  test('rejects invalid process ids', () {
    expect(() => _script(processId: 0), throwsArgumentError);
  });

  test('validates paths before passing them via the environment', () {
    expect(
      () => validateWindowsUpdateHelperPath(
        r'relative\setup.exe',
        name: 'installerPath',
        extension: '.exe',
      ),
      throwsArgumentError,
    );
    expect(
      () => validateWindowsUpdateHelperPath(
        r'C:\Temp\setup" & calc.exe',
        name: 'installerPath',
      ),
      throwsArgumentError,
    );
    expect(
      () => validateWindowsUpdateHelperPath(
        'C:\\Temp\\setup.exe\nwhoami',
        name: 'installerPath',
      ),
      throwsArgumentError,
    );
    expect(
      () => validateWindowsUpdateHelperPath(
        r'C:\Temp\setup.zip',
        name: 'installerPath',
        extension: '.exe',
      ),
      throwsArgumentError,
    );
    expect(
      () => validateWindowsUpdateHelperPath(
        r'C:\Temp\setup.exe',
        name: 'installerPath',
        extension: '.exe',
      ),
      returnsNormally,
    );
    // 环境变量只展开一次；路径中的 % 不会再次被当成变量。
    expect(
      () => validateWindowsUpdateHelperPath(
        r'C:\Temp\100%\setup.exe',
        name: 'installerPath',
        extension: '.exe',
      ),
      returnsNormally,
    );
  });
}
