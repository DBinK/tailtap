import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection.dart';

class TunnelTask {
  TunnelTask(this.id, this.config);
  final String id;
  final ConnectionConfig config;
  final DateTime started = DateTime.now();
  String state = 'starting', address = '', error = '', bind = '127.0.0.1';
  int localPort = 0, clients = 0, up = 0, down = 0;
  bool? targetReady;
  Process? process;
  Timer? autoStop;
  final List<String> logs = [];
  bool get active => !['stopped', 'failed', 'conflict'].contains(state);
  String get label => switch (state) {
    'starting' => '启动中',
    'sharing' => '分享中',
    'running' => '运行中',
    'waiting' => '等待远端',
    'stopping' => '停止中',
    'stopped' => '已停止',
    'conflict' => '端口冲突',
    _ => '启动失败',
  };
  String get localAddress => '$bind:$localPort';
}

final tasksProvider = ChangeNotifierProvider<Tasks>((ref) => Tasks());

class Tasks extends ChangeNotifier {
  Tasks() {
    if (Platform.isAndroid) {
      _events = const EventChannel('dev.tailtap/events')
          .receiveBroadcastStream()
          .listen((event) {
            final data = Map<String, dynamic>.from(event as Map);
            final task = tasks.where((t) => t.id == data['id']).firstOrNull;
            if (task != null) {
              applyEvent(task, data);
            }
          });
    }
    load();
  }
  StreamSubscription<dynamic>? _events;
  static const _channel = MethodChannel('dev.tailtap/core');
  final List<TunnelTask> tasks = [];
  final List<ConnectionConfig> recent = [], favorites = [];
  String executable = '';
  bool loaded = false;
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    executable = prefs.getString('corePath') ?? '';
    for (final entry in [('recent', recent), ('favorites', favorites)]) {
      for (final raw in prefs.getStringList(entry.$1) ?? <String>[]) {
        try {
          entry.$2.add(
            ConnectionConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>),
          );
        } catch (_) {
          /* Ignore incompatible saved configurations. */
        }
      }
    }
    if (Platform.isAndroid) {
      try {
        final live = await _channel.invokeListMethod<dynamic>('snapshot') ?? [];
        for (final item in live) {
          final event = Map<String, dynamic>.from(item as Map);
          final config = ConnectionConfig.fromJson(
            Map<String, dynamic>.from(event['config'] as Map),
          );
          final task = TunnelTask(event['id'] as String, config);
          tasks.add(task);
          applyEvent(task, event);
        }
      } on PlatformException {
        /* No native service is running. */
      }
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('corePath', executable);
    await prefs.setStringList('recent', recent.map((c) => c.encode()).toList());
    await prefs.setStringList(
      'favorites',
      favorites.map((c) => c.encode()).toList(),
    );
  }

  bool isFavorite(ConnectionConfig c) =>
      favorites.any((v) => v.encode() == c.encode());
  void favorite(ConnectionConfig c) {
    if (isFavorite(c)) {
      favorites.removeWhere((v) => v.encode() == c.encode());
    } else {
      favorites.add(c);
    }
    unawaited(save());
    notifyListeners();
  }

  Future<TunnelTask> start(ConnectionConfig config, {int minutes = 0}) async {
    final task = TunnelTask(
      DateTime.now().microsecondsSinceEpoch.toString(),
      config,
    );
    tasks.insert(0, task);
    notifyListeners();
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<void>('start', {
          'id': task.id,
          'config': {...config.toJson(), 'stopAfterSeconds': minutes * 60},
        });
        recent.removeWhere((c) => c.encode() == config.encode());
        recent.insert(0, config);
        if (recent.length > 12) {
          recent.removeLast();
        }
        unawaited(save());
        if (minutes > 0) {
          task.autoStop = Timer(Duration(minutes: minutes), () => stop(task));
        }
        return task;
      }
      if (Platform.isIOS) {
        throw const FormatException('iOS 原生核心尚未接入');
      }
      final bundled =
          '${File(Platform.resolvedExecutable).parent.path}/tailtap-core${Platform.isWindows ? '.exe' : ''}';
      final path = executable.isNotEmpty
          ? executable
          : File(bundled).existsSync()
          ? bundled
          : '${Directory.current.path}/core/bin/tailtap-core${Platform.isWindows ? '.exe' : ''}';
      final process = await Process.start(path, [], runInShell: false);
      task.process = process;
      if (task.state == 'stopping' || task.state == 'stopped') {
        process.kill();
        return task;
      }
      process.stdin.writeln(
        jsonEncode({...config.toJson(), 'stopAfterSeconds': minutes * 60}),
      );
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (['stopping', 'stopped'].contains(task.state)) {
              return;
            }
            try {
              applyEvent(task, jsonDecode(line) as Map<String, dynamic>);
            } catch (_) {
              task.error = '核心返回了无效事件';
              notifyListeners();
            }
          });
      // Core diagnostics can contain credentials. Do not retain stderr.
      process.stderr.listen((_) {});
      unawaited(
        process.exitCode.then((code) {
          if (!['failed', 'conflict', 'stopped'].contains(task.state)) {
            task.state = task.state == 'stopping' ? 'stopped' : 'failed';
            if (task.state == 'failed') {
              task.error = '核心进程已退出（$code），请重新启动';
            }
          }
          task.autoStop?.cancel();
          notifyListeners();
        }),
      );
      recent.removeWhere((c) => c.encode() == config.encode());
      recent.insert(0, config);
      if (recent.length > 12) {
        recent.removeLast();
      }
      unawaited(save());
      if (minutes > 0) {
        task.autoStop = Timer(Duration(minutes: minutes), () => stop(task));
      }
    } catch (e) {
      task.state = 'failed';
      task.error = e is FormatException
          ? e.message
          : e is PlatformException
          ? e.message ?? '原生核心错误'
          : '无法启动 Go 核心，请在设置中检查可执行文件路径。';
      notifyListeners();
    }
    return task;
  }

  void applyEvent(TunnelTask task, Map<String, dynamic> event) {
    if (['stopping', 'stopped'].contains(task.state) &&
        event['state'] != 'stopped') {
      return;
    }

    if (event['state'] != null) {
      task.state = event['state'] as String;
      if (task.state == 'stopped') {
        task.address = '';
      }
      task.logs.add(
        '${DateTime.now().toIso8601String().substring(11, 19)}  ${task.label}',
      );
      if (task.logs.length > 100) {
        task.logs.removeAt(0);
      }
    }
    task.address = event['address'] as String? ?? task.address;
    task.bind = event['bind'] as String? ?? task.bind;
    task.localPort = event['localPort'] as int? ?? task.localPort;
    task.clients = event['clients'] as int? ?? task.clients;
    task.up = event['up'] as int? ?? task.up;
    task.down = event['down'] as int? ?? task.down;
    if (event.containsKey('targetReady')) {
      task.targetReady = event['targetReady'] as bool?;
    }
    task.error = event['error'] as String? ?? task.error;
    notifyListeners();
  }

  Future<void> stop(TunnelTask task) async {
    if (task.state == 'stopped' || task.state == 'stopping') {
      return;
    }
    task.state = 'stopping';
    task.autoStop?.cancel();
    notifyListeners();
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('stop', {'id': task.id});
      } catch (e) {
        task.state = 'failed';
        task.error = '停止未完成，请重试：$e';
        notifyListeners();
        return;
      }
      task.state = 'stopped';
      task.address = '';
      notifyListeners();
      return;
    }
    final process = task.process;
    if (process != null) {
      await process.stdin.close();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        process.kill();
        await process.exitCode;
      }
    }
    task.state = 'stopped';
    task.address = '';
    notifyListeners();
  }

  Future<void> stopAll() async {
    await Future.wait(tasks.where((t) => t.active).map(stop));
  }

  @override
  void dispose() {
    _events?.cancel();
    for (final t in tasks) {
      t.autoStop?.cancel();
      t.process?.kill();
    }
    super.dispose();
  }
}
