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
  String path = '核心未报告连接路径';
  double? latencyMs;
  DateTime? measuredAt;
  String relay = '', diagnostic = '';
  bool checkFailed = false, checking = false;
  DateTime? diagnosticAt;
  List<Map<String, dynamic>> peers = [];
  List<Map<String, dynamic>> files = [];
  bool filesListed = false;
  final Map<String, Map<String, dynamic>> fileProgress = {};
  final Map<String, String> fileErrors = {};
  final Set<String> downloadedFiles = {};
  final Set<String> savingFiles = {};
  String destinationUri = '';
  String destinationPath = '';
  bool transferActive = false;
  int localPort = 0, clients = 0, up = 0, down = 0;
  bool? targetReady;
  bool? tunnelReady;
  DateTime? stopAt;
  DateTime? ended;
  Duration get duration => (ended ?? DateTime.now()).difference(started);
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
    if (Platform.isMacOS) {
      _tray.setMethodCallHandler((call) async {
        if (call.method == 'stopAll') await stopAll();
      });
    }
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
    _loading = load();
  }
  StreamSubscription<dynamic>? _events;
  static const _channel = MethodChannel('dev.tailtap/core');
  static const _tray = MethodChannel('dev.tailtap/tray');
  final List<TunnelTask> tasks = [];
  final List<ConnectionConfig> recent = [], favorites = [];
  String executable = '';
  bool loaded = false;
  late final Future<void> _loading;
  String? _lastTrayStatus;
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

  String get coreExecutable {
    final bundled =
        '${File(Platform.resolvedExecutable).parent.path}/tailtap-core${Platform.isWindows ? '.exe' : ''}';
    return executable.isNotEmpty
        ? executable
        : File(bundled).existsSync()
        ? bundled
        : '${Directory.current.path}/core/bin/tailtap-core${Platform.isWindows ? '.exe' : ''}';
  }

  Future<void> control(
    TunnelTask task,
    String action, {
    bool visible = false,
    List<String> files = const [],
    String directory = '',
  }) async {
    if (!task.active) return;
    final requestTime = DateTime.now();
    if (action == 'check') {
      if (task.checking) return;
      task.checking = true;
      task.checkFailed = false;
      task.diagnostic = '正在检查连接…';
      task.diagnosticAt = requestTime;
      notifyListeners();
      Future<void>.delayed(const Duration(seconds: 20), () {
        if (task.checking && task.diagnosticAt == requestTime) {
          task.checking = false;
          task.checkFailed = true;
          task.diagnostic = '检查未完成，请重试';
          notifyListeners();
        }
      });
    }
    final command = {
      'action': action,
      'visible': visible,
      if (files.isNotEmpty) 'files': files,
      if (directory.isNotEmpty) 'directory': directory,
    };
    if (action == 'download') {
      final previousDirectories = files
          .map((name) => task.fileProgress[name]?['directory'] as String?)
          .whereType<String>()
          .toSet();
      for (final path in previousDirectories) {
        final directory = Directory(path);
        if (await directory.exists()) await directory.delete(recursive: true);
      }
      for (final name in files) {
        task.fileErrors.remove(name);
      }
      task.transferActive = true;
      notifyListeners();
    }
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<bool>('control', {
          'id': task.id,
          'command': command,
        });
      } else {
        task.process?.stdin.writeln(jsonEncode(command));
      }
    } on StateError {
      /* The process may have just closed. */
      if (action == 'download') task.transferActive = false;
    } on PlatformException {
      /* Diagnostics must not stop a tunnel. */
      if (action == 'download') task.transferActive = false;
    } on MissingPluginException {
      /* No native core in widget tests. */
      if (action == 'download') task.transferActive = false;
    }
    if (action == 'download') notifyListeners();
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    if (Platform.isMacOS) unawaited(_syncMacTray());
  }

  Future<void> _syncMacTray() async {
    final active = tasks.where((task) => task.active).toList();
    final first = active.firstOrNull;
    final summary = first == null
        ? ''
        : '${first.config.title} · ${first.label}';
    final signature = '${active.length}|$summary';
    if (signature == _lastTrayStatus) return;
    _lastTrayStatus = signature;
    try {
      await _tray.invokeMethod<void>('setStatus', {
        'activeCount': active.length,
        'summary': summary,
      });
    } on MissingPluginException {
      // The macOS app may not have finished registering its status item yet.
    } on PlatformException {
      // Tray availability must not affect tunnel tasks.
    }
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
    await _loading;
    final task = TunnelTask(
      DateTime.now().microsecondsSinceEpoch.toString(),
      config,
    );
    if (minutes > 0) {
      task.stopAt = DateTime.now().add(Duration(minutes: minutes));
    }
    tasks.insert(0, task);
    notifyListeners();
    try {
      final coreConfig = {...config.toJson(), 'stopAfterSeconds': minutes * 60};
      if (!task.active || task.state == 'stopping') return task;
      if (Platform.isAndroid) {
        await _channel.invokeMethod<void>('start', {
          'id': task.id,
          'config': coreConfig,
        });
        if (config.kind != ServiceKind.file) {
          recent.removeWhere((c) => c.encode() == config.encode());
          recent.insert(0, config);
          if (recent.length > 12) recent.removeLast();
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
      process.stdin.writeln(jsonEncode(coreConfig));
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
              unawaited(_cleanupTaskFiles(task));
            }
          }
          task.autoStop?.cancel();
          task.ended ??= DateTime.now();
          notifyListeners();
        }),
      );
      if (config.kind != ServiceKind.file) {
        recent.removeWhere((c) => c.encode() == config.encode());
        recent.insert(0, config);
        if (recent.length > 12) recent.removeLast();
      }
      unawaited(save());
      if (minutes > 0) {
        task.autoStop = Timer(Duration(minutes: minutes), () => stop(task));
      }
    } catch (e) {
      task.state = 'failed';
      task.ended = DateTime.now();
      await _cleanupTaskFiles(task);
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
      final previous = task.state;
      task.state = event['state'] as String;
      if (task.state == 'failed') unawaited(_cleanupTaskFiles(task));
      if (task.state == 'stopped') {
        task.address = '';
        task.transferActive = false;
      }
      if (previous != task.state) _log(task, '状态 · ${task.label}');
      if (!task.active) task.ended ??= DateTime.now();
    }
    task.address = event['address'] as String? ?? task.address;
    task.bind = event['bind'] as String? ?? task.bind;
    task.localPort = event['localPort'] as int? ?? task.localPort;
    task.clients = event['clients'] as int? ?? task.clients;
    task.up = event['up'] as int? ?? task.up;
    task.down = event['down'] as int? ?? task.down;
    if (event.containsKey('targetReady')) {
      final ready = event['targetReady'] as bool?;
      if (ready != task.targetReady) {
        _log(
          task,
          '目标服务 · ${ready == null
              ? '尚未确认'
              : ready
              ? '可用'
              : '暂不可用'}',
        );
      }
      task.targetReady = ready;
    }
    final reportedPath = event['path'] as String?;
    if (reportedPath != null && reportedPath != 'unknown') {
      if (reportedPath != task.path) _log(task, '路径 · $reportedPath');
      task.path = reportedPath;
    }
    task.latencyMs = (event['latencyMs'] as num?)?.toDouble() ?? task.latencyMs;
    task.measuredAt =
        DateTime.tryParse(event['measuredAt'] as String? ?? '') ??
        task.measuredAt;
    task.relay = event['relay'] as String? ?? task.relay;
    task.checkFailed = event['checkFailed'] as bool? ?? task.checkFailed;
    if (event['peers'] is List) {
      task.peers = (event['peers'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    if (event['files'] is List) {
      task.filesListed = true;
      task.files = (event['files'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    if (event['fileProgress'] is Map) {
      final progress = Map<String, dynamic>.from(event['fileProgress'] as Map);
      final name = progress['name'] as String?;
      if (name != null) task.fileProgress[name] = progress;
    }
    if (event['fileError'] is String && event['error'] is String) {
      task.fileErrors[event['fileError'] as String] = event['error'] as String;
    }
    if (event['downloadDone'] == true) task.transferActive = false;
    if (event['fileComplete'] is String) {
      final name = event['fileComplete'] as String;
      if (task.destinationUri.isNotEmpty || task.destinationPath.isNotEmpty) {
        task.savingFiles.add(name);
        unawaited(_copyDownloadedFile(task, name));
      }
    }
    final diagnostic = event['diagnostic'] as String?;
    if (diagnostic != null) {
      final requested = task.checking;
      if (requested || diagnostic != task.diagnostic) _log(task, diagnostic);
      task.checking = false;
      task.diagnostic = diagnostic;
      task.diagnosticAt = DateTime.now();
    }
    final reportedError = event['error'] as String?;
    if (reportedError != null &&
        reportedError.isNotEmpty &&
        reportedError != task.error) {
      _log(task, '错误 · $reportedError');
    }
    task.error = reportedError ?? task.error;
    if (event.containsKey('tunnelReady')) {
      final ready = event['tunnelReady'] as bool?;
      if (ready != task.tunnelReady && ready == true) {
        _log(task, '隧道 · 已连通');
      }
      task.tunnelReady = ready;
    }
    notifyListeners();
  }

  Future<void> _copyDownloadedFile(TunnelTask task, String name) async {
    final progress = task.fileProgress[name];
    final directory = progress?['directory'] as String?;
    if (directory == null) return;
    try {
      if (Platform.isAndroid && task.destinationUri.isNotEmpty) {
        await _channel.invokeMethod<void>('copyToTree', {
          'treeUri': task.destinationUri,
          'sourcePath': '$directory${Platform.pathSeparator}$name',
          'name': name,
        });
      } else {
        final destination = Directory(task.destinationPath);
        var outputName = name;
        final dot = name.lastIndexOf('.');
        final stem = dot > 0 ? name.substring(0, dot) : name;
        final ext = dot > 0 ? name.substring(dot) : '';
        var suffix = 2;
        final source = File('$directory${Platform.pathSeparator}$name');
        late File target;
        while (true) {
          target = File(
            '${destination.path}${Platform.pathSeparator}$outputName',
          );
          try {
            await target.create(exclusive: true);
            break;
          } on FileSystemException {
            outputName = '$stem ($suffix)$ext';
            suffix++;
          }
        }
        final output = target.openWrite();
        try {
          await output.addStream(source.openRead());
          await output.flush();
        } catch (_) {
          await output.close();
          await target.delete().catchError((_) => target);
          rethrow;
        }
        try {
          await output.close();
        } catch (_) {
          await target.delete().catchError((_) => target);
          rethrow;
        }
      }
      final temporary = File('$directory${Platform.pathSeparator}$name');
      if (await temporary.exists()) await temporary.delete();
      task.downloadedFiles.add(name);
      task.fileErrors.remove(name);
      task.savingFiles.remove(name);
      notifyListeners();
    } on PlatformException catch (e) {
      task.fileErrors[name] = e.message ?? '无法保存到所选目录';
      task.error = task.fileErrors[name]!;
      task.savingFiles.remove(name);
      notifyListeners();
    } on FileSystemException catch (e) {
      task.fileErrors[name] = '无法保存文件：${e.message}';
      task.error = task.fileErrors[name]!;
      task.savingFiles.remove(name);
      notifyListeners();
    } catch (e) {
      task.fileErrors[name] = '无法保存文件：$e';
      task.error = task.fileErrors[name]!;
      task.savingFiles.remove(name);
      notifyListeners();
    }
  }

  Future<String?> pickDestination() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('pickDestination');
    } on PlatformException {
      return null;
    }
  }

  void _log(TunnelTask task, String message) {
    task.logs.add(
      '${DateTime.now().toLocal().toIso8601String().substring(11, 19)}  $message',
    );
    if (task.logs.length > 100) task.logs.removeAt(0);
  }

  Future<void> stop(TunnelTask task) async {
    if (task.state == 'stopped' || task.state == 'stopping') {
      return;
    }
    task.state = 'stopping';
    task.transferActive = false;
    _log(task, '正在停止任务');
    task.autoStop?.cancel();
    notifyListeners();
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('stop', {'id': task.id});
      } catch (e) {
        task.state = 'failed';
        task.ended ??= DateTime.now();
        task.error = '停止未完成，请重试：$e';
        notifyListeners();
        return;
      }
      task.state = 'stopped';
      task.ended ??= DateTime.now();
      task.address = '';
      await _cleanupTaskFiles(task);
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
    task.ended ??= DateTime.now();
    task.address = '';
    await _cleanupTaskFiles(task);
    notifyListeners();
  }

  Future<void> _cleanupTaskFiles(TunnelTask task) async {
    if (task.config.kind != ServiceKind.file) {
      return;
    }
    if (task.config.mode == 'share' && task.config.filesDir.isNotEmpty) {
      final directory = Directory(task.config.filesDir);
      if (await directory.exists()) await directory.delete(recursive: true);
      return;
    }
    final directories = task.fileProgress.values
        .map((progress) => progress['directory'] as String?)
        .whereType<String>()
        .toSet();
    for (final path in directories) {
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  Future<void> stopAll() async {
    await Future.wait(tasks.where((t) => t.active).map(stop));
  }

  void remove(TunnelTask task) {
    if (task.active) return;
    task.autoStop?.cancel();
    tasks.remove(task);
    notifyListeners();
  }

  void clearFinished() {
    for (final task in tasks.where((t) => !t.active)) {
      task.autoStop?.cancel();
    }
    tasks.removeWhere((t) => !t.active);
    notifyListeners();
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
