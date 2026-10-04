import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tail_tap/main.dart';
import 'package:tail_tap/core/tasks.dart';
import 'package:tail_tap/models/connection.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Connection intake collapses after recognition and can change entries',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      const address = 'tcABCDEFGHIJKLMNOPQRSTUV';
      for (final width in [320.0, 900.0]) {
        tester.view.physicalSize = Size(width, 1100);
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: ServiceEditor(connect: true)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).first,
          'tailcat forward $address 22',
        );
        await tester.pumpAndSettle();
        expect(find.text('端口 · 22'), findsOneWidget);
        expect(find.text('服务名称和用途由发送方提供，不代表已验证对方身份。请确认连接卡来源。'), findsOneWidget);
        expect(find.text('更多选项'), findsNothing);
        expect(tester.takeException(), isNull);
        expect(find.text('留空自动分配端口'), findsOneWidget);
        expect(find.text('更换连接入口'), findsOneWidget);
        expect(find.text('tailcat forward $address 22'), findsNothing);
        await tester.tap(find.text('更换连接入口'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, address);
        await tester.pumpAndSettle();
        expect(find.text('远端端口'), findsOneWidget);
        expect(find.text('连接'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
  testWidgets('Task detail has no nested task card and fits narrow screens', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final width in [320.0, 900.0]) {
      tester.view.physicalSize = Size(width, 1200);
      final task =
          TunnelTask(
              'detail',
              const ConnectionConfig(
                mode: 'connect',
                kind: ServiceKind.port,
                port: 22,
              ),
            )
            ..state = 'running'
            ..localPort = 2222;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: TaskDetail(task: task)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TaskCard), findsNothing);
      expect(find.text('远端端口 22 → 本机 127.0.0.1:2222'), findsOneWidget);
      expect(find.text('停止任务'), findsOneWidget);
      await tester.tap(find.text('连接诊断'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
  test('Repeated status snapshots do not duplicate events and end time stays fixed', () async {
    final store = Tasks();
    while (!store.loaded) {
      await Future<void>.delayed(Duration.zero);
    }
    final task = TunnelTask(
      'events',
      const ConnectionConfig(mode: 'connect', kind: ServiceKind.port, port: 22),
    );
    store.applyEvent(task, {'state': 'running'});
    store.applyEvent(task, {'state': 'running'});
    expect(task.logs.length, 1);
    store.applyEvent(task, {'state': 'stopped'});
    final ended = task.ended;
    final duration = task.duration;
    store.applyEvent(task, {'state': 'stopped'});
    expect(task.logs.length, 2);
    expect(task.ended, ended);
    expect(task.duration, duration);
    store.dispose();
  });
  testWidgets(
    'Share card fits mobile and desktop widths with one service label',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      const config = ConnectionConfig(
        mode: 'share',
        kind: ServiceKind.ssh,
        port: 22,
      );
      final task = TunnelTask('share', config)
        ..address = 'tcABCDEFGHIJKLMNOPQRSTUV';
      for (final width in [320.0, 900.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width < 800 ? width : 800,
                  child: ShareCardContent(
                    task: task,
                    card: config.card(task.address),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('服务：SSH · 22'), findsOneWidget);
        expect(find.text('复制连接卡'), findsOneWidget);
        expect(find.text('复制 Tailcat 命令'), findsOneWidget);
        expect(find.text('复制原始地址'), findsOneWidget);
        final shareY = tester.getTopLeft(find.text('分享')).dy;
        final addressY = tester.getTopLeft(find.text('复制原始地址')).dy;
        final commandY = tester.getTopLeft(find.text('复制 Tailcat 命令')).dy;
        final cardY = tester.getTopLeft(find.text('复制连接卡')).dy;
        expect(
          shareY < addressY && addressY < commandY && commandY < cardY,
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
  testWidgets(
    'Inactive task records can be removed without affecting active tasks',
    (tester) async {
      final store = Tasks();
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const config = ConnectionConfig(
        mode: 'share',
        kind: ServiceKind.ssh,
        port: 22,
      );
      final active = TunnelTask('active', config)..state = 'sharing';
      final stopped = TunnelTask('stopped', config)..state = 'stopped';
      final conflict = TunnelTask('conflict', config)..state = 'conflict';
      store.tasks.addAll([active, stopped, conflict]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [tasksProvider.overrideWith((ref) => store)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('删除记录').first);
      await tester.tap(find.text('删除记录').first);
      await tester.pumpAndSettle();
      expect(store.tasks, [active, conflict]);
      await tester.ensureVisible(find.text('清空记录'));
      await tester.tap(find.text('清空记录'));
      await tester.pumpAndSettle();
      expect(store.tasks, [active]);
      expect(find.text('已结束与异常'), findsNothing);
    },
  );
  testWidgets('Home groups QR scanning under connection intake', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();
    expect(find.text('TailTap'), findsOneWidget);
    expect(find.text('分享服务'), findsOneWidget);
    expect(find.text('连接服务'), findsOneWidget);
    expect(find.text('扫码连接'), findsNothing);
    expect(find.text('下一次连接，从这里开始'), findsOneWidget);
    await tester.tap(find.text('分享服务'));
    await tester.pumpAndSettle();
    expect(find.text('目标端口'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('启动并生成连接卡'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('启动并生成连接卡'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 1–65535 的端口'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接服务'));
    await tester.pumpAndSettle();
    expect(find.text('扫描二维码'), findsOneWidget);
  });
  testWidgets('Invalid pasted entry remains editable and never starts', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接服务'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'invalid-link');
    await tester.pumpAndSettle();
    expect(
      find.text('请输入 TailTap 连接卡、Tailcat 地址或 tailcat forward 命令'),
      findsOneWidget,
    );
    expect(find.text('invalid-link'), findsOneWidget);
  });
}
