import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/tasks.dart';
import 'models/connection.dart';

const ink = Color(0xff172b29);
const green = Color(0xff166b58);
final navigatorKey = GlobalKey<NavigatorState>();
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppLinks().uriLinkStream.listen((uri) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context != null && uri.scheme == 'tailtap') {
        openEditor(context, connect: true, input: uri.toString());
      }
    });
  });
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    title: 'TailTap',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff6f7f3),
      colorScheme: ColorScheme.fromSeed(
        seedColor: green,
        primary: green,
        surface: Colors.white,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: ink, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(color: ink, fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xfff3f5f1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
    home: const Home(),
  );
}

void message(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
Future<void> copy(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    message(context, '已复制');
  }
}

IconData kindIcon(ServiceKind kind) => switch (kind) {
  ServiceKind.port => Icons.swap_horiz_rounded,
  ServiceKind.ssh => Icons.terminal_rounded,
  ServiceKind.web => Icons.language_rounded,
};

class Home extends ConsumerWidget {
  const Home({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(tasksProvider);
    final active = store.tasks.where((t) => t.active).length;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1060),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: green,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.hub_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'TailTap',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '设置',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const Settings(),
                        ),
                      ),
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                Text(
                  '让服务，触手可及。',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 10),
                const Text(
                  '分享一个端口，连接另一台设备。',
                  style: TextStyle(color: Color(0xff6c7c76), fontSize: 16),
                ),
                const SizedBox(height: 26),
                LayoutBuilder(
                  builder: (context, c) {
                    final items = [
                      action(
                        context,
                        '分享服务',
                        '把本机服务带到远端',
                        Icons.north_east_rounded,
                        true,
                        () => openEditor(context),
                      ),
                      action(
                        context,
                        '连接服务',
                        '粘贴入口，开始使用',
                        Icons.south_west_rounded,
                        false,
                        () => openEditor(context, connect: true),
                      ),
                    ];
                    return c.maxWidth > 620
                        ? Row(
                            children: [
                              Expanded(child: items[0]),
                              const SizedBox(width: 16),
                              Expanded(child: items[1]),
                            ],
                          )
                        : Column(
                            children: [
                              items[0],
                              const SizedBox(height: 12),
                              items[1],
                            ],
                          );
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => scan(context),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('扫码连接'),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text('正在运行', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(width: 10),
                    Chip(label: Text('$active')),
                    const Spacer(),
                    if (active > 0)
                      TextButton(
                        onPressed: store.stopAll,
                        child: const Text('停止全部'),
                      ),
                  ],
                ),
                if (store.tasks.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 40,
                        horizontal: 24,
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.route_rounded,
                            size: 40,
                            color: green,
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            '下一次连接，从这里开始',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '分享本机端口，或粘贴收到的连接入口。',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => openEditor(context),
                            child: const Text('创建第一个分享'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...store.tasks.map((t) => TaskCard(task: t)),
                const SizedBox(height: 28),
                Text('收藏', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                if (store.favorites.isEmpty)
                  const Text(
                    '在任务详情中收藏常用配置。',
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  ...store.favorites.map((c) => saved(context, c, ref)),
                const SizedBox(height: 28),
                Text('最近使用', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                if (store.recent.isEmpty)
                  const Text(
                    '启动后的配置会保存在这里。',
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  ...store.recent.map((c) => saved(context, c, ref)),
                const SizedBox(height: 32),
                const Text(
                  'TCP 隧道 · WireGuard 加密 · 临时身份',
                  style: TextStyle(fontSize: 12, color: Color(0xff81918a)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget action(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    bool primary,
    VoidCallback tap,
  ) => Material(
    color: primary ? green : Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Icon(icon, color: primary ? Colors.white : green, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: primary ? Colors.white : ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: primary ? Colors.white70 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_rounded,
              color: primary ? Colors.white : green,
            ),
          ],
        ),
      ),
    ),
  );
  Widget saved(BuildContext context, ConnectionConfig c, WidgetRef ref) => Card(
    child: ListTile(
      leading: Icon(kindIcon(c.kind), color: green),
      title: Text(c.title),
      subtitle: Text(
        '${c.mode == 'share' ? '分享' : '连接'} · ${c.mode == 'share' ? c.host : '远端'}:${c.port}',
      ),
      trailing: const Icon(Icons.arrow_forward_rounded),
      onTap: () => openEditor(context, connect: c.mode == 'connect', config: c),
    ),
  );
}

void openEditor(
  BuildContext context, {
  bool connect = false,
  ConnectionConfig? config,
  String? input,
}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) =>
        ServiceEditor(connect: connect, initial: config, input: input),
  ),
);
Future<void> scan(BuildContext context) async {
  if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
    message(context, '此平台请使用粘贴入口');
    return;
  }
  final value = await Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => const ScanPage()),
  );
  if (value != null && context.mounted) {
    openEditor(context, connect: true, input: value);
  }
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫码连接')),
    body: MobileScanner(
      onDetect: (capture) {
        final raw = capture.barcodes.firstOrNull?.rawValue;
        if (!done && raw != null) {
          done = true;
          Navigator.pop(context, raw);
        }
      },
    ),
  );
}

class TaskCard extends ConsumerWidget {
  const TaskCard({super.key, required this.task});
  final TunnelTask task;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = task;
    final sharing = t.config.mode == 'share';
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => TaskDetail(task: t)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(kindIcon(t.config.kind), color: green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t.config.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    t.label,
                    style: TextStyle(color: t.active ? green : Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                sharing
                    ? '${t.config.host}:${t.config.port}'
                    : '${t.localPort == 0 ? '准备本机监听' : t.localAddress} → 远端 :${t.config.port}',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              Text(
                sharing
                    ? '${t.clients} 个连接 · ${targetLabel(t)}'
                    : '路径未知 · ${targetLabel(t)}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              if (t.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    t.error,
                    style: const TextStyle(color: Colors.deepOrange),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  if (sharing && t.address.isNotEmpty)
                    FilledButton.tonalIcon(
                      onPressed: () => shareCard(context, t),
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('分享'),
                    ),
                  if (!sharing && t.localPort > 0 && t.active)
                    TextButton.icon(
                      onPressed: () => copy(context, t.localAddress),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('复制地址'),
                    ),
                  if (!sharing &&
                      t.config.kind == ServiceKind.web &&
                      t.state == 'running')
                    TextButton(
                      onPressed: () => openWeb(context, t),
                      child: const Text('打开网页'),
                    ),
                  if (t.active)
                    TextButton(
                      onPressed: () => ref.read(tasksProvider).stop(t),
                      child: const Text('停止'),
                    ),
                  if (!t.active)
                    TextButton(
                      onPressed: () => openEditor(
                        context,
                        connect: !sharing,
                        config: t.config,
                      ),
                      child: const Text('重新配置'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String targetLabel(TunnelTask t) => t.targetReady == null
    ? '目标尚未检查'
    : t.targetReady!
    ? '目标可用'
    : '目标服务不可用';
Future<void> openWeb(BuildContext context, TunnelTask t) async {
  final uri = Uri(
    scheme: t.config.webScheme,
    host: '127.0.0.1',
    port: t.localPort,
    path: t.config.webPath,
  );
  if (!await launchUrl(uri) && context.mounted) {
    message(context, '无法打开浏览器，请复制地址');
  }
}

Future<void> shareCard(BuildContext context, TunnelTask t) async {
  final address = t.address;
  if (address.isEmpty) return;
  final card = t.config.card(address);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.config.title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(targetLabel(t)),
            const SizedBox(height: 16),
            QrImageView(data: card, size: 220, backgroundColor: Colors.white),
            const SizedBox(height: 12),
            const Text(
              '入口包含访问凭据，请只分享给可信的人。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text: card,
                      sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
                    ),
                  ),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('系统分享'),
                ),
                OutlinedButton(
                  onPressed: () => copy(ctx, card),
                  child: const Text('复制连接卡'),
                ),
                TextButton(
                  onPressed: () => copy(ctx, address),
                  child: const Text('原始地址'),
                ),
                TextButton(
                  onPressed: () =>
                      copy(ctx, 'tailcat forward $address ${t.config.port}'),
                  child: const Text('CLI 命令'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class ServiceEditor extends ConsumerStatefulWidget {
  const ServiceEditor({
    super.key,
    required this.connect,
    this.initial,
    this.input,
  });
  final bool connect;
  final ConnectionConfig? initial;
  final String? input;
  @override
  ConsumerState<ServiceEditor> createState() => _ServiceEditorState();
}

class _ServiceEditorState extends ConsumerState<ServiceEditor> {
  final form = GlobalKey<FormState>();
  final host = TextEditingController(text: '127.0.0.1'),
      port = TextEditingController(),
      local = TextEditingController(),
      name = TextEditingController(),
      entry = TextEditingController(),
      webPath = TextEditingController(text: '/');
  ServiceKind kind = ServiceKind.port;
  bool lan = false, parsed = false, busy = false;
  String? error;
  String address = '', scheme = 'http';
  int minutes = 0;
  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      fill(widget.initial!);
    }
    if (widget.input != null) {
      entry.text = widget.input!;
      parse();
    }
  }

  void fill(ConnectionConfig c) {
    kind = c.kind;
    host.text = c.host;
    port.text = c.port == 0 ? '' : '${c.port}';
    local.text = c.localPort == 0 ? '' : '${c.localPort}';
    name.text = c.name;
    address = c.address;
    lan = c.lan;
    scheme = c.webScheme;
    webPath.text = c.webPath;
    parsed = c.address.isNotEmpty;
    if (parsed) {
      entry.text = c.address;
    }
  }

  void parse() {
    try {
      fill(ConnectionConfig.parse(entry.text));
      error = null;
    } on FormatException catch (e) {
      error = e.message;
      parsed = false;
    }
    setState(() {});
  }

  @override
  void dispose() {
    for (final c in [host, port, local, name, entry, webPath]) {
      c.dispose();
    }
    super.dispose();
  }

  String? validatePort(String? s, {bool optional = false}) {
    if (optional && (s == null || s.isEmpty)) return null;
    final p = int.tryParse(s ?? '');
    return p == null || p < 1 || p > 65535 ? '请输入 1–65535 的端口' : null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.connect ? '连接服务' : '分享服务')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.connect ? '把远端服务带到本机' : '选择你要分享的服务',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              if (widget.connect) ...[
                TextField(
                  controller: entry,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => setState(() => parsed = false),
                  decoration: const InputDecoration(
                    labelText: '连接入口',
                    hintText: 'tailtap://connect?... 或 tc…',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data != null) {
                          entry.text = data.text ?? '';
                          parse();
                        }
                      },
                      icon: const Icon(Icons.content_paste),
                      label: const Text('粘贴'),
                    ),
                    const Spacer(),
                    FilledButton.tonal(
                      onPressed: parse,
                      child: const Text('解析入口'),
                    ),
                  ],
                ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.deepOrange),
                  ),
                if (error != null &&
                    Uri.tryParse(entry.text)?.queryParameters['address'] !=
                        null)
                  TextButton(
                    onPressed: () => copy(
                      context,
                      Uri.parse(entry.text).queryParameters['address']!,
                    ),
                    child: const Text('复制卡片中的原始地址'),
                  ),
                const SizedBox(height: 20),
              ],
              SegmentedButton<ServiceKind>(
                segments: ServiceKind.values
                    .map(
                      (k) => ButtonSegment(
                        value: k,
                        label: Text(k.label),
                        icon: Icon(kindIcon(k)),
                      ),
                    )
                    .toList(),
                selected: {kind},
                onSelectionChanged: (v) => setState(() {
                  kind = v.first;
                  if (port.text.isEmpty) {
                    port.text = kind == ServiceKind.ssh
                        ? '22'
                        : kind == ServiceKind.web
                        ? '80'
                        : '';
                  }
                }),
              ),
              const SizedBox(height: 24),
              if (kind == ServiceKind.ssh) ...[
                const Text(
                  '分享现有 SSH 服务，沿用原账户与认证。',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('SSH · 22'),
                      onPressed: () => setState(() => port.text = '22'),
                    ),
                    ActionChip(
                      label: const Text('Termux · 8022'),
                      onPressed: () => setState(() => port.text = '8022'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (!widget.connect) ...[
                TextFormField(
                  controller: host,
                  decoration: const InputDecoration(labelText: '目标地址'),
                  validator: (s) =>
                      s == null || s.trim().isEmpty ? '请输入 IP 或主机名' : null,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: port,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: widget.connect ? '远端端口' : '目标端口',
                ),
                validator: (s) => validatePort(s),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: '名称（可选）'),
              ),
              const SizedBox(height: 16),
              if (widget.connect) ...[
                TextFormField(
                  controller: local,
                  onChanged: (_) => setState(() => useFreePort = false),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '本机端口',
                    hintText: kind == ServiceKind.web
                        ? '留空使用空闲端口'
                        : '留空优先使用远端同号端口',
                  ),
                  validator: (s) => validatePort(s, optional: true),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() {
                    local.text = '';
                    useFreePort = true;
                  }),
                  child: const Text('使用空闲端口（网页默认）'),
                ),
              ],
              if (kind == ServiceKind.web) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: scheme,
                  items: ['http', 'https']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => scheme = v!,
                  decoration: const InputDecoration(labelText: '网页协议'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: webPath,
                  decoration: const InputDecoration(labelText: '网页路径'),
                  validator: (s) =>
                      s == null ||
                          !s.startsWith('/') ||
                          s.startsWith('//') ||
                          s.contains('\\')
                      ? '请输入以 / 开始的本机路径'
                      : null,
                ),
              ],
              const SizedBox(height: 16),
              ExpansionTile(
                title: const Text('更多选项'),
                tilePadding: EdgeInsets.zero,
                children: [
                  if (widget.connect)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('允许局域网访问'),
                      subtitle: const Text('监听 0.0.0.0，其他设备可连接本机端口'),
                      value: lan,
                      onChanged: (v) => setState(() => lan = v),
                    )
                  else
                    DropdownButtonFormField<int>(
                      initialValue: minutes,
                      decoration: const InputDecoration(labelText: '自动停止'),
                      items: [0, 15, 30, 60]
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(m == 0 ? '手动停止' : '$m 分钟后'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => minutes = v!,
                    ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('临时身份'),
                    subtitle: Text('每次分享生成新入口，停止后入口失效。'),
                  ),
                ],
              ),
              if (widget.connect && parsed)
                Card(
                  color: const Color(0xffe7f1e9),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '本次操作：${kind.label} TCP 映射\n远端 :${port.text} → 本机 ${lan ? '0.0.0.0' : '127.0.0.1'}\n名称和用途由发送端提供，不代表已验证身份。',
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: busy ? null : start,
                icon: const Icon(Icons.arrow_forward),
                label: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(widget.connect ? '确认并连接' : '启动并分享'),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '分享后不自动发送入口。目标可用性与隧道状态分别检查。',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> start() async {
    if (widget.connect && !parsed) {
      parse();
      if (!parsed) return;
    }
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    final p = int.parse(port.text);
    final config = ConnectionConfig(
      mode: widget.connect ? 'connect' : 'share',
      kind: kind,
      port: p,
      host: host.text.trim(),
      name: name.text.trim(),
      address: address,
      localPort: local.text.isEmpty
          ? (kind == ServiceKind.web || useFreePort ? 0 : p)
          : int.parse(local.text),
      lan: lan,
      webScheme: scheme,
      webPath: webPath.text,
    );
    final t = await ref.read(tasksProvider).start(config, minutes: minutes);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TaskDetail(task: t, showShare: !widget.connect),
      ),
    );
  }

  bool useFreePort = false;
}

class TaskDetail extends ConsumerStatefulWidget {
  const TaskDetail({super.key, required this.task, this.showShare = false});
  final TunnelTask task;
  final bool showShare;
  @override
  ConsumerState<TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends ConsumerState<TaskDetail> {
  bool opened = false, webOpened = false;
  @override
  Widget build(BuildContext context) {
    final store = ref.watch(tasksProvider);
    final t = widget.task;
    if (widget.showShare && !opened && t.address.isNotEmpty && t.active) {
      opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) shareCard(context, t);
      });
    }
    if (t.config.kind == ServiceKind.web &&
        t.config.mode == 'connect' &&
        t.state == 'running' &&
        !webOpened) {
      webOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openWeb(context, t);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务详情'),
        actions: [
          IconButton(
            tooltip: '收藏配置',
            onPressed: () => store.favorite(t.config),
            icon: Icon(
              store.isFavorite(t.config)
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TaskCard(task: t),
              const SizedBox(height: 24),
              Text('连接状态', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              info(
                '本机监听',
                t.config.mode == 'share'
                    ? '无需本机监听'
                    : t.localPort > 0 && t.active
                    ? t.localAddress
                    : '未监听',
              ),
              info('目标服务', targetLabel(t)),
              info('连接路径', '未知'),
              info(
                '持续时间',
                '${DateTime.now().difference(t.started).inMinutes} 分钟',
              ),
              info('已完成流量', '↑ ${t.up} B   ↓ ${t.down} B'),
              if (t.config.kind == ServiceKind.ssh &&
                  t.config.mode == 'connect' &&
                  t.localPort > 0 &&
                  t.active)
                OutlinedButton.icon(
                  onPressed: () =>
                      copy(context, 'ssh -p ${t.localPort} <用户名>@127.0.0.1'),
                  icon: const Icon(Icons.terminal),
                  label: const Text('复制 SSH 命令'),
                ),
              if (t.state == 'conflict')
                FilledButton.tonal(
                  onPressed: () =>
                      openEditor(context, connect: true, config: t.config),
                  child: const Text('修改本机端口'),
                ),
              const SizedBox(height: 24),
              Text('事件日志', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    t.logs.isEmpty ? '等待核心事件…' : t.logs.join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      height: 1.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '停止后释放本任务的连接。最近使用只保存配置，不恢复运行状态。',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget info(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: Colors.grey)),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class Settings extends ConsumerStatefulWidget {
  const Settings({super.key});
  @override
  ConsumerState<Settings> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<Settings> {
  late final path = TextEditingController(
    text: ref.read(tasksProvider).executable,
  );
  @override
  void dispose() {
    path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('核心与平台', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.memory_rounded),
              title: Text('tailcat v0.7.0'),
              subtitle: Text(
                '桌面：Go 独立进程 · NDJSON IPC\nAndroid：共享 Go 核心 · JNI · 前台服务',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: path,
              decoration: const InputDecoration(
                labelText: 'Go 核心路径（可选）',
                hintText: '留空使用内置核心',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final store = ref.read(tasksProvider);
                store.executable = path.text.trim();
                await store.save();
                if (context.mounted) message(context, '设置已保存');
              },
              child: const Text('保存'),
            ),
            const SizedBox(height: 32),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('身份与后台'),
              subtitle: Text('当前使用临时身份。桌面任务随应用退出结束。固定身份、自定义中继与内置终端尚未开放。'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('扫码权限'),
              subtitle: Text('仅在打开扫码页面时使用相机。连接卡与原始地址不写入事件日志。'),
            ),
          ],
        ),
      ),
    ),
  );
}
