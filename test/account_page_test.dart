import 'package:flutter/material.dart';
import 'package:flutter_music/app/providers.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/features/account/account_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpAccountPage(
    WidgetTester tester, {
    String savedAddress = '',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 用静态值代替 Drift 查询，避免测试收尾时流查询关闭定时器残留。
          accountProvider.overrideWith((ref) => Stream<Account?>.value(null)),
          backendBaseUrlProvider.overrideWithValue(
            AsyncValue.data(savedAddress),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: AccountPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('已保存的后端地址默认不显示在登录页', (tester) async {
    await pumpAccountPage(tester, savedAddress: 'http://192.168.1.10:5080');

    expect(find.text('高级设置'), findsOneWidget);
    expect(find.text('服务器地址'), findsNothing);
    expect(find.textContaining('192.168.1.10'), findsNothing);

    await tester.tap(find.text('高级设置'));
    await tester.pumpAndSettle();

    expect(find.text('服务器地址'), findsOneWidget);
    expect(find.text('http://192.168.1.10:5080'), findsOneWidget);
    expect(find.text('收起服务器设置'), findsOneWidget);
  });

  testWidgets('未配置后端地址时直接展开地址输入框', (tester) async {
    await pumpAccountPage(tester);

    expect(find.text('服务器地址'), findsOneWidget);
    expect(find.text('请填写服务器地址后登录'), findsOneWidget);
    expect(find.text('高级设置'), findsNothing);
  });
}
