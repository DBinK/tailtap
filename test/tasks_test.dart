import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tail_tap/core/tasks.dart';
import 'package:tail_tap/models/connection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Tasks> loadedStore() async {
    final store = Tasks();
    while (!store.loaded) {
      await Future<void>.delayed(Duration.zero);
    }
    return store;
  }

  test('Retrying a failed file clears its aggregate error', () async {
    final store = await loadedStore();
    final task = TunnelTask(
      'retry',
      const ConnectionConfig(
        mode: 'connect',
        kind: ServiceKind.file,
        port: 2222,
      ),
    )..state = 'running';
    store.applyEvent(task, {'fileError': 'a.txt', 'error': '文件下载失败：连接中断'});
    expect(task.error, '文件下载失败：连接中断');

    await store.control(task, 'download', files: ['a.txt']);

    expect(task.fileErrors, isEmpty);
    expect(task.error, isEmpty);
    store.dispose();
  });

  test('Retrying keeps an aggregate error raised outside the file', () async {
    final store = await loadedStore();
    final task = TunnelTask(
      'retry-unrelated',
      const ConnectionConfig(
        mode: 'connect',
        kind: ServiceKind.file,
        port: 2222,
      ),
    )..state = 'running';
    store.applyEvent(task, {'fileError': 'a.txt', 'error': '文件下载失败：连接中断'});
    // A later core-level failure replaces the aggregate message.
    store.applyEvent(task, {'error': '核心进程已退出（1），请重新启动'});

    await store.control(task, 'download', files: ['a.txt']);

    expect(task.fileErrors, isEmpty);
    expect(task.error, '核心进程已退出（1），请重新启动');
    store.dispose();
  });

  test('An event-driven stop releases the staged files', () async {
    final store = await loadedStore();
    final staged = await Directory.systemTemp.createTemp('tailtap-staged');
    await File('${staged.path}${Platform.pathSeparator}a.txt')
        .writeAsString('x');
    final task = TunnelTask(
      'stop-event',
      ConnectionConfig(
        mode: 'share',
        kind: ServiceKind.file,
        port: 2222,
        filesDir: staged.path,
      ),
    )..state = 'sharing';

    store.applyEvent(task, {'state': 'stopped'});

    for (var i = 0; i < 50 && await staged.exists(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(await staged.exists(), isFalse);
    store.dispose();
  });
}
