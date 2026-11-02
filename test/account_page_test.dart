import 'package:flutter/material.dart';
import 'package:flutter_music/app/providers.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/features/account/account_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpAccountPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 用静态值代替 Drift 查询，避免测试收尾时流查询关闭定时器残留。
          accountProvider.overrideWith((ref) => Stream<Account?>.value(null)),
        ],
        child: const MaterialApp(home: Scaffold(body: AccountPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('登录页只保留账号与密码，不展示服务器地址', (tester) async {
    await pumpAccountPage(tester);

    expect(find.text('服务器地址'), findsNothing);
    expect(find.text('高级设置'), findsNothing);
    expect(find.textContaining('zonwe.top'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('账号或邮箱'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
  });
}
