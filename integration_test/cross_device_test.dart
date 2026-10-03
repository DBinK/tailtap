import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tail_tap/main.dart';
import 'package:tail_tap/core/tasks.dart';

const controlPort = int.fromEnvironment('TAILTAP_COORDINATOR_PORT');
Future<Map<String, dynamic>> control(
  String key, [
  Map<String, dynamic>? value,
]) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('http://127.0.0.1:$controlPort/$key');
    final request = value == null
        ? await client.getUrl(uri)
        : await client.postUrl(uri);
    if (value != null) {
      request.headers.contentType = ContentType.json;
      final payload = utf8.encode(jsonEncode(value));
      request.contentLength = payload.length;
      request.add(payload);
    }
    final response = await request.close();
    return jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> awaitControl(String key) async {
  final deadline = DateTime.now().add(const Duration(minutes: 4));
  while (DateTime.now().isBefore(deadline)) {
    final data = await control(key);
    if (data.isNotEmpty) {
      return data;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  throw TimeoutException('Other device did not publish $key');
}

Future<void> until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Tunnel startup timed out');
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

Future<String> fetch(int port) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/'));
    final response = await request.close().timeout(const Duration(seconds: 20));
    return await utf8.decoder.bind(response).join();
  } finally {
    client.close(force: true);
  }
}

Future<void> shareFromUI(WidgetTester tester, int port, String name) async {
  navigatorKey.currentState!.popUntil((route) => route.isFirst);
  await tester.pumpAndSettle();
  await tester.tap(find.text('分享服务'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, '目标端口'), '$port');
  await tester.enterText(find.widgetWithText(TextFormField, '名称（可选）'), name);
  await tester.scrollUntilVisible(
    find.text('启动并分享'),
    250,
    scrollable: find
        .descendant(
          of: find.byType(ServiceEditor),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(find.text('启动并分享'));
  await tester.pumpAndSettle();
}

Future<void> connectFromUI(WidgetTester tester, String card) async {
  navigatorKey.currentState!.popUntil((route) => route.isFirst);
  await tester.pumpAndSettle();
  await tester.tap(find.text('连接服务'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, '连接入口'), card);
  await tester.tap(find.text('解析入口'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('使用空闲端口（网页默认）'),
    250,
    scrollable: find
        .descendant(
          of: find.byType(ServiceEditor),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(find.text('使用空闲端口（网页默认）'));
  await tester.scrollUntilVisible(
    find.text('确认并连接'),
    250,
    scrollable: find
        .descendant(
          of: find.byType(ServiceEditor),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(find.text('确认并连接'));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Mac and Android connect in both directions through the product UI',
    (tester) async {
      expect(controlPort, greaterThan(0));
      await tester.pumpWidget(const ProviderScope(child: MyApp()));
      await tester.pumpAndSettle();
      final store = ProviderScope.containerOf(tester.element(find.byType(Home)))
          .read(tasksProvider);
      await until(tester, () => store.loaded);
      HttpServer? target;
      try {
        if (Platform.isMacOS) {
          final host = await control('host-target');
          await shareFromUI(tester, host['port'] as int, 'Mac → Android · 验证');
          final share = store.tasks.first;
          await until(
            tester,
            () => share.address.isNotEmpty || share.state == 'failed',
          );
          expect(share.state, 'sharing', reason: share.error);
          await control('mac-share', {
            'card': share.config.card(share.address),
          });
          await awaitControl('android-to-mac-pass');
          final remote = await awaitControl('android-share');
          await connectFromUI(tester, remote['card'] as String);
          final connect = store.tasks.first;
          await until(
            tester,
            () => connect.state == 'running' || connect.state == 'failed',
          );
          expect(connect.state, 'running', reason: connect.error);
          expect(await fetch(connect.localPort), 'TAILTAP_ANDROID_TARGET');
          await control('mac-to-android-pass', {'passed': true});
          await awaitControl('android-finished');
        } else {
          final remote = await awaitControl('mac-share');
          await connectFromUI(tester, remote['card'] as String);
          final connect = store.tasks.first;
          await until(
            tester,
            () => connect.state == 'running' || connect.state == 'failed',
          );
          expect(connect.state, 'running', reason: connect.error);
          expect(await fetch(connect.localPort), 'TAILTAP_MAC_TARGET');
          await control('android-to-mac-pass', {'passed': true});
          final termux = await control('termux-target');
          int targetPort;
          if (termux.isNotEmpty) {
            targetPort = termux['port'] as int;
          } else {
            target = await HttpServer.bind('127.0.0.1', 0);
            target.listen((request) {
              request.response.write('TAILTAP_ANDROID_TARGET');
              unawaited(request.response.close());
            });
            targetPort = target.port;
          }
          await shareFromUI(tester, targetPort, 'Android → Mac · 验证');
          final share = store.tasks.first;
          await until(
            tester,
            () => share.address.isNotEmpty || share.state == 'failed',
          );
          expect(share.state, 'sharing', reason: share.error);
          await control('android-share', {
            'card': share.config.card(share.address),
          });
          await awaitControl('mac-to-android-pass');
          await store.stopAll();
          await control('android-finished', {'finished': true});
        }
      } finally {
        await store.stopAll();
        await target?.close(force: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
