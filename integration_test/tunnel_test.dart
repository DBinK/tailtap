import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tail_tap/main.dart';
import 'package:tail_tap/core/tasks.dart';
import 'package:tail_tap/models/connection.dart';

Future<void> until(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Core readiness timeout');
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

Future<String> echo(int port, String payload) async {
  final socket = await Socket.connect(
    '127.0.0.1',
    port,
    timeout: const Duration(seconds: 15),
  );
  try {
    socket.write(payload);
    return utf8.decode(await socket.first.timeout(const Duration(seconds: 15)));
  } finally {
    socket.destroy();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Real JNI tunnel, conflicts, background and isolated cleanup', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();
    expect(find.text('分享服务'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Home)),
    );
    final store = container.read(tasksProvider);
    await until(tester, () => store.loaded);
    final target = await ServerSocket.bind('127.0.0.1', 0);
    final sockets = <Socket>[];
    final subscription = target.listen((socket) {
      sockets.add(socket);
      socket.listen((data) {
        socket.add(utf8.encode('echo:${utf8.decode(data)}'));
      });
    });
    try {
      final share = await store.start(
        ConnectionConfig(
          mode: 'share',
          kind: ServiceKind.port,
          port: target.port,
          name: '实机测试 · TCP',
        ),
      );
      await until(
        tester,
        () => share.address.isNotEmpty || share.state == 'failed',
      );
      expect(share.state, 'sharing', reason: share.error);
      await until(tester, () => share.targetReady != null);
      expect(share.targetReady, isTrue);
      final parsed = ConnectionConfig.parse(share.config.card(share.address));
      final connect = await store.start(
        ConnectionConfig(
          mode: 'connect',
          kind: parsed.kind,
          port: parsed.port,
          address: parsed.address,
          localPort: 0,
          name: '实机测试 · 连接',
        ),
      );
      await until(
        tester,
        () => connect.state == 'running' || connect.state == 'failed',
      );
      expect(connect.state, 'running', reason: connect.error);
      expect(
        await echo(connect.localPort, 'TailTap on Android'),
        'echo:TailTap on Android',
      );
      final conflict = await store.start(
        ConnectionConfig(
          mode: 'connect',
          kind: ServiceKind.port,
          port: parsed.port,
          address: parsed.address,
          localPort: connect.localPort,
        ),
      );
      await until(
        tester,
        () => conflict.state == 'conflict' || conflict.state == 'failed',
      );
      expect(conflict.state, 'conflict', reason: conflict.error);
      await store.stop(conflict);
      // The host harness moves the activity to the background during this window.
      // Addresses and connection cards are deliberately never printed.
      // ignore: avoid_print
      print('TAILTAP_BACKGROUND_WINDOW');
      await Future<void>.delayed(const Duration(seconds: 6));
      expect(await echo(connect.localPort, 'background'), 'echo:background');
      // ignore: avoid_print
      print('TAILTAP_BACKGROUND_PASS');
      await Future<void>.delayed(const Duration(seconds: 3));
      final localPort = connect.localPort;
      await store.stop(connect);
      expect(connect.state, 'stopped');
      final released = await ServerSocket.bind('127.0.0.1', localPort);
      await released.close();
      expect(share.state, 'sharing');
      await store.stop(share);
      expect(share.address, isEmpty);
      final restarted = await store.start(share.config);
      await until(
        tester,
        () => restarted.address.isNotEmpty || restarted.state == 'failed',
      );
      expect(restarted.state, 'sharing', reason: restarted.error);
      expect(restarted.address, isNot(parsed.address));
      await store.stop(restarted);
      await store.stop(restarted);
      expect(restarted.state, 'stopped');
    } finally {
      await store.stopAll();
      for (final socket in sockets) {
        socket.destroy();
      }
      await subscription.cancel();
      await target.close();
    }
  });
}
