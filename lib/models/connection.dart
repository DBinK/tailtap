import 'dart:convert';

enum ServiceKind { port, ssh, web }

extension ServiceLabel on ServiceKind {
  String get label => switch (this) {
    ServiceKind.port => '端口',
    ServiceKind.ssh => 'SSH',
    ServiceKind.web => '网页',
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
  });
  final String mode, host, name, address, webScheme, webPath;
  final ServiceKind kind;
  final int port, localPort;
  final bool lan;
  String get title => name.isEmpty ? '${kind.label} · $port' : name;
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
      if (kind == ServiceKind.web) ...{'scheme': webScheme, 'path': webPath},
    },
  ).toString();
  static ConnectionConfig parse(String input) {
    input = input.trim();
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
      throw const FormatException('请输入 TailTap 连接卡或原始 tailcat 地址');
    }
    final q = uri.queryParameters;
    if (q['v'] != '1') {
      throw const FormatException('连接卡版本不兼容，可复制卡片中的原始地址');
    }
    final address = q['address'] ?? '';
    if (!RegExp(r'^tc[A-Za-z0-9_-]{20,4096}$').hasMatch(address)) {
      throw const FormatException('连接卡中的 tailcat 地址无效');
    }
    final port = int.tryParse(q['port'] ?? '') ?? 0;
    if (port < 1 || port > 65535) {
      throw const FormatException('远端端口范围为 1–65535');
    }
    final kind = ServiceKind.values
        .where((k) => k.name == q['kind'])
        .firstOrNull;
    if (kind == null) {
      throw const FormatException('尚不支持此服务类型');
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
      localPort: kind == ServiceKind.web ? 0 : port,
      address: address,
      name: q['name'] ?? '',
      webScheme: scheme,
      webPath: path,
    );
  }

  String encode() => jsonEncode(toJson());
}
