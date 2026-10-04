import 'dart:convert';

enum ServiceKind { port, ssh, web, file }

extension ServiceLabel on ServiceKind {
  String get label => switch (this) {
    ServiceKind.port => '端口',
    ServiceKind.ssh => 'SSH',
    ServiceKind.web => '网页',
    ServiceKind.file => '文件',
  };
}

class ConnectionConfig {
  const ConnectionConfig({
    required this.mode,
    required this.kind,
    required this.port,
    this.host = '127.0.0.1',
    this.name = '',
    this.address = '',
    this.localPort = 0,
    this.lan = false,
    this.webScheme = 'http',
    this.webPath = '/',
    this.sshUser = '',
    this.filesDir = '',
  });
  final String mode, host, name, address, webScheme, webPath;
  final String sshUser;
  final String filesDir;
  final ServiceKind kind;
  final int port, localPort;
  final bool lan;
  String get title => name.isEmpty
      ? kind == ServiceKind.file
            ? '文件分享'
            : '${kind.label} · $port'
      : name;

  ConnectionConfig copyWith({
    String? mode,
    ServiceKind? kind,
    int? port,
    String? host,
    String? name,
    String? address,
    int? localPort,
    bool? lan,
    String? webScheme,
    String? webPath,
    String? sshUser,
    String? filesDir,
  }) => ConnectionConfig(
    mode: mode ?? this.mode,
    kind: kind ?? this.kind,
    port: port ?? this.port,
    host: host ?? this.host,
    name: name ?? this.name,
    address: address ?? this.address,
    localPort: localPort ?? this.localPort,
    lan: lan ?? this.lan,
    webScheme: webScheme ?? this.webScheme,
    webPath: webPath ?? this.webPath,
    sshUser: sshUser ?? this.sshUser,
    filesDir: filesDir ?? this.filesDir,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'kind': kind.name,
    'port': port,
    'host': host,
    'name': name,
    'address': address,
    'localPort': localPort,
    'lan': lan,
    'webScheme': webScheme,
    'webPath': webPath,
    'sshUser': sshUser,
    'filesDir': filesDir,
  };
  factory ConnectionConfig.fromJson(Map<String, dynamic> j) => ConnectionConfig(
    mode: j['mode'] as String,
    kind: ServiceKind.values.byName(j['kind'] as String),
    port: j['port'] as int,
    host: j['host'] as String? ?? '127.0.0.1',
    name: j['name'] as String? ?? '',
    address: j['address'] as String? ?? '',
    localPort: j['localPort'] as int? ?? 0,
    lan: j['lan'] as bool? ?? false,
    webScheme: j['webScheme'] as String? ?? 'http',
    webPath: j['webPath'] as String? ?? '/',
    sshUser: j['sshUser'] as String? ?? '',
    filesDir: j['filesDir'] as String? ?? '',
  );
  String card(String addr) => Uri(
    scheme: 'tailtap',
    host: 'connect',
    queryParameters: {
      'v': '1',
      'address': addr,
      'kind': kind.name,
      'port': '$port',
      'name': title,
      if (kind == ServiceKind.ssh && sshUser.isNotEmpty) 'user': sshUser,
      if (kind == ServiceKind.web) ...{'scheme': webScheme, 'path': webPath},
    },
  ).toString();
  static ConnectionConfig parse(String input) {
    input = input
        .replaceAll(RegExp(r'&#(?:x20|32);', caseSensitive: false), ' ')
        .trim();
    final command = RegExp(
      r'^tailcat\s+forward\s+(tc[A-Za-z0-9_-]{20,4096})\s+(\d{1,5})$',
    ).firstMatch(input);
    if (command != null) {
      final port = int.parse(command.group(2)!);
      if (port < 1 || port > 65535) {
        throw const FormatException('远端端口范围为 1–65535');
      }
      return ConnectionConfig(
        mode: 'connect',
        kind: ServiceKind.port,
        port: port,
        localPort: 0,
        address: command.group(1)!,
      );
    }
    if (RegExp(r'^tc[A-Za-z0-9_-]{20,4096}$').hasMatch(input)) {
      return ConnectionConfig(
        mode: 'connect',
        kind: ServiceKind.port,
        port: 0,
        address: input,
      );
    }
    final uri = Uri.tryParse(input);
    if (uri == null || uri.scheme != 'tailtap' || uri.host != 'connect') {
      throw const FormatException(
        '请输入 TailTap 连接卡、Tailcat 地址或 tailcat forward 命令',
      );
    }
    final q = uri.queryParameters;
    if (q['v'] != '1') {
      throw const FormatException('连接卡版本不兼容，可复制卡片中的原始地址');
    }
    final address = q['address'] ?? '';
    if (!RegExp(r'^tc[A-Za-z0-9_-]{20,4096}$').hasMatch(address)) {
      throw const FormatException('连接卡中的 tailcat 地址无效');
    }
    final kind = ServiceKind.values
        .where((k) => k.name == q['kind'])
        .firstOrNull;
    if (kind == null) {
      throw const FormatException('尚不支持此服务类型');
    }
    final port = int.tryParse(q['port'] ?? '') ?? 0;
    if (port < 1 || port > 65535) {
      throw const FormatException('远端端口范围为 1–65535');
    }
    final user = q['user'] ?? '';
    if (user.isNotEmpty && !validSshUser(user)) {
      throw const FormatException('SSH 用户名无效');
    }
    final scheme = q['scheme'] ?? 'http';
    final path = q['path'] ?? '/';
    if (!['http', 'https'].contains(scheme) ||
        !path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains('\\')) {
      throw const FormatException('网页参数无效');
    }
    return ConnectionConfig(
      mode: 'connect',
      kind: kind,
      port: port,
      localPort: 0,
      address: address,
      name: q['name'] ?? '',
      sshUser: user,
      webScheme: scheme,
      webPath: path,
    );
  }

  static bool validSshUser(String value) =>
      RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.$-]{0,63}$').hasMatch(value);

  String sshCommand(int listenPort) => sshUser.isEmpty
      ? 'ssh -p $listenPort <用户名>@127.0.0.1'
      : "ssh -p $listenPort '$sshUser@127.0.0.1'";

  String encode() => jsonEncode(toJson());
}
