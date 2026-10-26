import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_music/app/providers.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/core/update/app_version.dart';
import 'package:flutter_music/core/update/update_manifest.dart';
import 'package:flutter_music/core/update/update_service.dart';
import 'package:flutter_music/core/update/update_settings.dart';
import 'package:flutter_music/features/update/startup_update_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late _FakeUpdateService service;
  late ProviderContainer container;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    service = _FakeUpdateService(update: _availableUpdate());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        appUpdateServiceProvider.overrideWithValue(service),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<void> pumpGate(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: StartupUpdateGate(child: Scaffold(body: Text('home'))),
        ),
      ),
    );
    // 启动检查有 2 秒延迟；之后还有设置读取、下载和弹窗等异步步骤。
    // 多推进一次时间，确保延迟计时器在上一轮异步初始化完成后才被创建。
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    for (var index = 0; index < 5; index++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('auto downloads an update when explicitly enabled', (
    tester,
  ) async {
    await database.setSetting(updateAutoDownloadSettingKey, 'true');

    await pumpGate(tester);

    expect(service.checkCalls, 1);
    expect(service.downloadCalls, 1);
    expect(find.textContaining('发现新版本'), findsOneWidget);
    expect(find.textContaining('后台自动下载'), findsOneWidget);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
  });

  testWidgets('checks by default but leaves downloading to the user', (
    tester,
  ) async {
    await pumpGate(tester);

    expect(service.checkCalls, 1);
    expect(service.downloadCalls, 0);
    expect(find.textContaining('发现新版本'), findsOneWidget);
    expect(find.text('下载并安装'), findsOneWidget);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
  });

  testWidgets('does not touch the update source when auto check is off', (
    tester,
  ) async {
    await database.setSetting(updateAutoCheckSettingKey, 'false');

    await pumpGate(tester);

    expect(service.checkCalls, 0);
    expect(service.downloadCalls, 0);
    expect(find.textContaining('发现新版本'), findsNothing);
  });

  testWidgets('portable builds only prompt and never auto download', (
    tester,
  ) async {
    await database.setSetting(updateAutoDownloadSettingKey, 'true');
    service.installed = false;

    await pumpGate(tester);

    expect(service.checkCalls, 1);
    expect(service.downloadCalls, 0);
    expect(find.textContaining('发现新版本'), findsOneWidget);
    expect(find.textContaining('当前是解压版'), findsOneWidget);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
  });

  testWidgets('records the attempt even when the startup check fails', (
    tester,
  ) async {
    service.checkError = const UpdateException('网络不可用');

    await pumpGate(tester);

    expect(service.checkCalls, 1);
    final lastCheck = await database.readSetting(updateLastCheckAtSettingKey);
    expect(DateTime.tryParse(lastCheck ?? ''), isNotNull);
    expect(find.textContaining('发现新版本'), findsNothing);
  });

  testWidgets('shows the download failure with a retry action', (tester) async {
    await database.setSetting(updateAutoDownloadSettingKey, 'true');
    service.downloadError = const UpdateException('网络中断，请稍后重试。');

    await pumpGate(tester);

    expect(service.downloadCalls, 1);
    expect(find.textContaining('网络中断'), findsOneWidget);
    expect(find.text('重新下载'), findsOneWidget);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });
}

class _FakeUpdateService implements AppUpdateService {
  _FakeUpdateService({required this.update});

  final UpdateAvailable update;
  bool supported = true;
  bool installed = true;
  Object? downloadError;
  Object? checkError;
  int checkCalls = 0;
  int downloadCalls = 0;

  @override
  bool get isSupported => supported;

  @override
  bool get isInstalled => installed;

  @override
  String get platformLabel => 'Windows x64';

  @override
  bool get requiresAppExit => false;

  @override
  String get installHint => '测试环境不会真的安装。';

  @override
  Future<AppVersion> currentVersion() async => update.current;

  @override
  Future<UpdateCheckResult> checkForUpdates() async {
    checkCalls++;
    final failure = checkError;
    if (failure != null) throw failure;
    return update;
  }

  @override
  Future<String> downloadUpdate(
    UpdateAsset asset, {
    UpdateProgressCallback? onProgress,
  }) async {
    downloadCalls++;
    final failure = downloadError;
    if (failure != null) throw failure;
    onProgress?.call(asset.size, asset.size);
    return r'C:\Temp\SimulGrooveMusic-update.exe';
  }

  @override
  Future<void> launchInstaller({
    required String installerPath,
    required AppVersion targetVersion,
  }) async {}

  @override
  Future<String?> takePendingFailure() async => null;

  @override
  Future<void> dispose() async {}
}

UpdateAvailable _availableUpdate() {
  final asset = UpdateAsset(
    uri: Uri.parse(
      'https://github.com/zonwe/SimulGroove-Music/releases/download/'
      'v1.2.0/SimulGrooveMusic-Setup-1.2.0.exe',
    ),
    size: 1024,
    sha256: 'a' * 64,
    kind: UpdateAssetKind.installer,
  );
  final release = UpdateRelease(
    version: AppVersion.parse('1.2.0+5'),
    publishedAt: DateTime.utc(2026, 10, 21),
    notes: '- 测试更新',
    assets: {'windows-x64': asset},
  );
  return UpdateAvailable(
    current: AppVersion.parse('1.1.0+4'),
    release: release,
    asset: asset,
  );
}
