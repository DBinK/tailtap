import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tail_tap/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Home offers share, connect and scan without fabricated tasks', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();
    expect(find.text('TailTap'), findsOneWidget);
    expect(find.text('分享服务'), findsOneWidget);
    expect(find.text('连接服务'), findsOneWidget);
    expect(find.text('扫码连接'), findsOneWidget);
    expect(find.text('下一次连接，从这里开始'), findsOneWidget);
    await tester.tap(find.text('分享服务'));
    await tester.pumpAndSettle();
    expect(find.text('目标端口'), findsOneWidget);
    await tester.ensureVisible(find.text('启动并分享'));
    await tester.tap(find.text('启动并分享'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 1–65535 的端口'), findsOneWidget);
  });
  testWidgets('Invalid pasted entry remains editable and never starts', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接服务'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'invalid-link');
    await tester.tap(find.text('解析入口'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 TailTap 连接卡或原始 tailcat 地址'), findsOneWidget);
    expect(find.text('invalid-link'), findsOneWidget);
  });
}
