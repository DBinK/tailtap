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

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : const Color(0xffedf2ee),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(error ? Icons.error_outline : Icons.info_outline, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

Widget formSwitch({
  required String title,
  required String subtitle,
  required bool value,
  required ValueChanged<bool>? onChanged,
}) => Material(
  color: const Color(0xfff3f5f1),
  borderRadius: BorderRadius.circular(14),
  clipBehavior: Clip.antiAlias,
  child: SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: onChanged,
  ),
);
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
        floatingLabelBehavior: FloatingLabelBehavior.always,
        alignLabelWithHint: true,
        filled: true,
        fillColor: const Color(0xfff3f5f1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
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
    final finished = store.tasks.where((t) => !t.active).toList();
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
                  '分享与连接服务',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 10),
                const Text(
                  'TailTap 基于 Tailcat，在设备之间分享和连接 TCP 服务。',
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
                        '粘贴连接卡或扫码',
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
                if (active == 0)
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
                  ...store.tasks
                      .where((t) => t.active)
                      .map((t) => TaskCard(task: t)),
                if (finished.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text(
                        '已结束与异常',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: store.clearFinished,
                        child: const Text('清空记录'),
                      ),
                    ],
                  ),
                  ...finished.map((t) => TaskCard(task: t)),
                ],
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
    clipBehavior: Clip.antiAlias,
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
Future<String?> scan(BuildContext context) async {
  if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
    message(context, '此平台请使用粘贴入口');
    return null;
  }
  return Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => const ScanPage()),
  );
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
    body: Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            final raw = capture.barcodes.firstOrNull?.rawValue;
            if (!done && raw != null) {
              done = true;
              Navigator.pop(context, raw);
            }
          },
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 28,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '将 TailTap 连接卡放入取景框。相机只在此页面开启；扫描后会先显示连接参数供你确认。',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
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
                    : '远端端口 ${t.config.port} → ${t.localPort == 0 ? '准备本机监听' : t.localAddress}',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              Text(
                sharing
                    ? '${t.clients} 个连接 · ${targetLabel(t)}'
                    : '${t.path} · ${targetLabel(t)}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              if (t.stopAt case final stopAt?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '计划 ${stopAt.hour.toString().padLeft(2, '0')}:${stopAt.minute.toString().padLeft(2, '0')} 自动停止',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              if (t.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Notice(t.error, error: true),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    if (t.active)
                      TextButton(
                        onPressed: () => ref.read(tasksProvider).stop(t),
                        child: const Text('停止'),
                      ),

                    if (sharing && t.address.isNotEmpty)
                      FilledButton.icon(
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
                    if (!sharing && t.state == 'conflict')
                      FilledButton.tonal(
                        onPressed: () => ref
                            .read(tasksProvider)
                            .start(t.config.copyWith(localPort: 0)),
                        child: const Text('自动分配端口并重试'),
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
                    if (!t.active)
                      TextButton.icon(
                        onPressed: () => ref.read(tasksProvider).remove(t),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('删除记录'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
  final wide = MediaQuery.sizeOf(context).width >= 700;
  if (wide) {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            child: ShareCardContent(task: t, card: card),
          ),
        ),
      ),
    );
  } else {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: ShareCardContent(task: t, card: card),
        ),
      ),
    );
  }
}

class ShareCardContent extends StatelessWidget {
  const ShareCardContent({super.key, required this.task, required this.card});
  final TunnelTask task;
  final String card;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      final qr = QrImageView(
        data: card,
        size: wide ? 320 : (constraints.maxWidth - 48).clamp(160, 240),
        padding: const EdgeInsets.all(12),
        backgroundColor: Colors.white,
      );
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.config.name.isEmpty
                ? '服务：${task.config.kind.label} · ${task.config.port}'
                : '服务：${task.config.name}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (task.config.name.isNotEmpty)
            Text(
              '${task.config.kind.label} · ${task.config.port}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          const Text('用另一台设备的 TailTap 扫码，或将连接卡粘贴到“连接服务”。'),
          const SizedBox(height: 8),
          const Notice('仅分享给可信的人，停止分享后连接卡失效。'),
          if (task.targetReady == false) ...[
            const SizedBox(height: 8),
            const Notice('目标服务暂不可用，请确认服务已启动。', error: true),
          ],
        ],
      );
      final buttons = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Builder(
            builder: (buttonContext) => FilledButton.tonalIcon(
              onPressed: () {
                final box = buttonContext.findRenderObject() as RenderBox;
                SharePlus.instance.share(
                  ShareParams(
                    text: card,
                    sharePositionOrigin:
                        box.localToGlobal(Offset.zero) & box.size,
                  ),
                );
              },
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text('分享'),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => copy(context, task.address),
            icon: const Icon(Icons.link, size: 18),
            label: const Text('复制原始地址'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => copy(
              context,
              'tailcat forward ${task.address} ${task.config.port}',
            ),
            icon: const Icon(Icons.terminal, size: 18),
            label: const Text('复制 Tailcat 命令'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => copy(context, card),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('复制连接卡'),
          ),
        ],
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '分享连接卡',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  qr,
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      children: [text, const SizedBox(height: 12), buttons],
                    ),
                  ),
                ],
              )
            else ...[
              text,
              const SizedBox(height: 16),
              Center(child: qr),
              const SizedBox(height: 20),
              buttons,
            ],
          ],
        ),
      );
    },
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
      webPath = TextEditingController(text: '/'),
      sshUser = TextEditingController();
  ServiceKind kind = ServiceKind.port;
  bool lan = false, parsed = false, rawAddress = false, busy = false;
  bool editingEntry = false;
  String? error;
  String address = '', scheme = 'http';
  int minutes = 0;
  @override
  void initState() {
    super.initState();
    if (!widget.connect && !Platform.isAndroid) {
      sshUser.text =
          Platform.environment['USER'] ??
          Platform.environment['USERNAME'] ??
          '';
    }
    if (widget.initial != null) {
      fill(widget.initial!);
    }
    if (widget.input != null) {
      entry.text = widget.input!;
      parse(showError: false, rebuild: false);
    }
  }

  void fill(ConnectionConfig c) {
    kind = c.kind;
    host.text = c.host;
    port.text = c.port == 0 ? '' : '${c.port}';
    local.text = c.localPort == 0 ? '' : '${c.localPort}';
    name.text =
        ServiceKind.values.any((k) => c.name == '${k.label} · ${c.port}')
        ? ''
        : c.name;
    address = c.address;
    lan = c.lan;
    scheme = c.webScheme;
    webPath.text = c.webPath;
    sshUser.text = c.sshUser;
    parsed = c.address.isNotEmpty;
    rawAddress = parsed && c.port == 0;
    if (parsed) {
      entry.text = c.address;
    }
  }

  void parse({bool showError = true, bool rebuild = true}) {
    try {
      final input = entry.text;
      final config = ConnectionConfig.parse(input);
      fill(config);
      entry.text = input;
      rawAddress = config.port == 0;
      local.clear();
      editingEntry = false;
      error = null;
    } on FormatException catch (e) {
      error = showError && entry.text.trim().isNotEmpty ? e.message : null;
      parsed = false;
      rawAddress = false;
    }
    if (rebuild && mounted) setState(() {});
  }

  Future<void> pasteEntry() async {
    final data = await Clipboard.getData('text/plain');
    if (data == null) return;
    entry.text = data.text ?? '';
    parse();
  }

  Future<void> scanEntry() async {
    final value = await scan(context);
    if (value == null || !mounted) return;
    entry.text = value;
    parse();
  }

  @override
  void dispose() {
    for (final c in [host, port, local, name, entry, webPath, sshUser]) {
      c.dispose();
    }
    super.dispose();
  }

  String? validatePort(String? s, {bool optional = false}) {
    if (optional && (s == null || s.isEmpty)) return null;
    final p = int.tryParse(s ?? '');
    return p == null || p < 1 || p > 65535 ? '请输入 1–65535 的端口' : null;
  }

  Widget connectionEditor(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('连接服务')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (!parsed || editingEntry) ...[
                const Text('粘贴连接卡、Tailcat 地址或命令，也可扫描二维码。'),
                const SizedBox(height: 16),
                TextField(
                  controller: entry,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => parse(showError: true),
                  decoration: InputDecoration(
                    labelText: '连接入口',
                    hintText: 'tailtap://connect?... 或 tailcat forward tc… 22',
                    errorText: error,
                    errorMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: pasteEntry,
                      icon: const Icon(Icons.content_paste),
                      label: const Text('粘贴'),
                    ),
                    if (Platform.isAndroid ||
                        Platform.isIOS ||
                        Platform.isMacOS)
                      OutlinedButton.icon(
                        onPressed: scanEntry,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('扫描二维码'),
                      ),
                  ],
                ),
              ],
              if (parsed && !editingEntry) ...[
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(kindIcon(kind), color: green),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                name.text.isEmpty
                                    ? '${kind.label}${port.text.isEmpty ? '' : ' · ${port.text}'}'
                                    : name.text,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                        if (name.text.isNotEmpty && !rawAddress)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('${kind.label} · 远端端口 ${port.text}'),
                          ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => setState(() => editingEntry = true),
                          icon: const Icon(Icons.swap_horiz, size: 18),
                          label: const Text('更换连接入口'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Notice('服务名称和用途由发送方提供，不代表已验证对方身份。请确认连接卡来源。'),
                const SizedBox(height: 24),
                Text('本机配置', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                serviceKinds(),
                if (kind == ServiceKind.ssh) ...[
                  const SizedBox(height: 16),
                  sshUserField(),
                ],
                const SizedBox(height: 16),
                if (rawAddress) ...[
                  TextFormField(
                    controller: port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '远端端口',
                      hintText: '请输入要访问的服务端口',
                    ),
                    validator: validatePort,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: local,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '本机端口',
                    hintText: '留空自动分配端口',
                  ),
                  validator: (s) => validatePort(s, optional: true),
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!rawAddress) ...[
                      TextFormField(
                        controller: port,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '远端端口'),
                        validator: validatePort,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: '名称（可选）',
                        hintText: '为这个连接取一个名称',
                      ),
                    ),
                    if (kind == ServiceKind.web) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: scheme,
                        decoration: const InputDecoration(labelText: '网页协议'),
                        items: ['http', 'https']
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                        onChanged: (v) => scheme = v!,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: webPath,
                        decoration: const InputDecoration(
                          labelText: '浏览器打开路径',
                          helperText: '默认 /，仅决定浏览器打开的页面。',
                        ),
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
                    formSwitch(
                      title: '允许局域网访问',
                      subtitle: '局域网设备可访问此本机端口。',
                      value: lan,
                      onChanged: (v) => setState(() => lan = v),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final button = FilledButton.icon(
                      onPressed: busy ? null : start,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('连接'),
                    );
                    return constraints.maxWidth < 400
                        ? SizedBox(width: double.infinity, child: button)
                        : Align(
                            alignment: Alignment.centerRight,
                            child: button,
                          );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => widget.connect
      ? connectionEditor(context)
      : Scaffold(
          appBar: AppBar(title: const Text('分享服务')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Form(
                key: form,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(kindIcon(kind), color: green),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '分享${kind.label}服务',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text('选择本机或可访问的设备服务，生成连接卡。'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Notice('连接卡包含访问凭据，请仅分享给可信的人。停止分享后连接卡失效。'),
                    const SizedBox(height: 24),
                    Text(
                      '目标配置',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    serviceKinds(),
                    if (kind == ServiceKind.ssh) ...[
                      const SizedBox(height: 16),
                      sshUserField(),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: host,
                      decoration: const InputDecoration(
                        labelText: '目标地址',
                        hintText: '127.0.0.1 或设备的 IP 地址',
                      ),
                      validator: (s) =>
                          s == null || s.trim().isEmpty ? '请输入 IP 或主机名' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '目标端口',
                        hintText: '例如 22 或 8080',
                      ),
                      validator: validatePort,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: minutes,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '自动停止分享'),
                      items: [0, 15, 30, 60]
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(m == 0 ? '手动停止' : '$m 分钟后'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => minutes = v!),
                    ),
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: name,
                          decoration: const InputDecoration(
                            labelText: '名称（可选）',
                            hintText: '为这个分享取一个名称',
                          ),
                        ),
                        if (kind == ServiceKind.web) ...[
                          const SizedBox(height: 16),
                          ...webFields(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),
                    editorAction(context, '启动并生成连接卡'),
                  ],
                ),
              ),
            ),
          ),
        );

  Widget sshUserField() => TextFormField(
    controller: sshUser,
    decoration: const InputDecoration(
      labelText: 'SSH 用户名（可选）',
      hintText: '目标服务的登录用户名',
    ),
    validator: (value) =>
        value == null ||
            value.trim().isEmpty ||
            ConnectionConfig.validSshUser(value.trim())
        ? null
        : '请输入有效的 SSH 用户名',
  );

  Widget serviceKinds() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('服务用途', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      SegmentedButton<ServiceKind>(
        segments: ServiceKind.values
            .map(
              (value) => ButtonSegment(
                value: value,
                label: Text(value.label),
                icon: Icon(kindIcon(value), size: 18),
              ),
            )
            .toList(),
        selected: {kind},
        showSelectedIcon: false,
        onSelectionChanged: busy
            ? null
            : (selection) => setState(() {
                kind = selection.single;
                if (!widget.connect && port.text.isEmpty) {
                  port.text = kind == ServiceKind.ssh
                      ? '22'
                      : kind == ServiceKind.web
                      ? '80'
                      : '';
                }
              }),
      ),
    ],
  );

  List<Widget> webFields() => [
    DropdownButtonFormField<String>(
      initialValue: scheme,
      decoration: const InputDecoration(labelText: '网页协议'),
      items: [
        'http',
        'https',
      ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
      onChanged: (v) => scheme = v!,
    ),
    const SizedBox(height: 16),
    TextFormField(
      controller: webPath,
      decoration: const InputDecoration(
        labelText: '浏览器打开路径',
        helperText: '默认 /，仅决定浏览器打开的页面。',
      ),
      validator: (s) =>
          s == null ||
              !s.startsWith('/') ||
              s.startsWith('//') ||
              s.contains('\\')
          ? '请输入以 / 开始的本机路径'
          : null,
    ),
  ];
  Widget editorAction(BuildContext context, String label) => LayoutBuilder(
    builder: (context, constraints) {
      final button = FilledButton.icon(
        onPressed: busy ? null : start,
        icon: const Icon(Icons.arrow_forward, size: 18),
        label: Text(label),
      );
      return constraints.maxWidth < 400
          ? SizedBox(width: double.infinity, child: button)
          : Align(alignment: Alignment.centerRight, child: button);
    },
  );

  Future<void> start() async {
    if (widget.connect && !parsed) {
      parse();
      if (!parsed) return;
    }
    if (!form.currentState!.validate()) return;
    if (validatePort(port.text) != null) {
      message(context, '请输入 1–65535 的远端端口');
      return;
    }
    if (widget.connect &&
        kind == ServiceKind.web &&
        (!webPath.text.startsWith('/') ||
            webPath.text.startsWith('//') ||
            webPath.text.contains('\\'))) {
      message(context, '请输入以 / 开始的本机路径');
      return;
    }
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
          ? (widget.connect ? 0 : p)
          : int.parse(local.text),
      lan: lan,
      webScheme: scheme,
      webPath: webPath.text,
      sshUser: kind == ServiceKind.ssh ? sshUser.text.trim() : '',
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
}

class TaskDetail extends ConsumerStatefulWidget {
  const TaskDetail({super.key, required this.task, this.showShare = false});
  final TunnelTask task;
  final bool showShare;
  @override
  ConsumerState<TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends ConsumerState<TaskDetail>
    with WidgetsBindingObserver {
  late final Tasks taskStore;
  bool opened = false, webOpened = false;
  Timer? clock;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    taskStore = ref.read(tasksProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref
              .read(tasksProvider)
              .control(widget.task, 'visible', visible: true),
        );
      }
    });
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.task.active) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(taskStore.control(widget.task, 'visible'));
    clock?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      taskStore.control(
        widget.task,
        'visible',
        visible: state == AppLifecycleState.resumed,
      ),
    );
  }

  String clockTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  String statusDescription(TunnelTask t) => switch (t.state) {
    'starting' => '正在准备连接，请稍候。',
    'sharing' => '分享入口已就绪，可将连接卡发送给另一台设备。',
    'running' =>
      t.tunnelReady == true ? '隧道已连通，可通过本机地址访问远端服务。' : '本机监听已就绪；远端服务是否可用尚未确认。',
    'waiting' => '本机监听已保留，正在等待远端服务恢复。',
    'stopping' => '正在关闭连接。',
    'stopped' => '任务已停止，可重新配置并启动。',
    'conflict' => '本机端口被占用，可自动分配新端口重试。',
    _ => '任务未能运行，请查看异常原因或展开诊断。',
  };
  Widget detailSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
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
            tooltip: store.isFavorite(t.config) ? '取消收藏配置' : '收藏配置',
            onPressed: () => store.favorite(t.config),
            icon: Icon(
              store.isFavorite(t.config)
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
            ),
          ),
          if (!t.active)
            PopupMenuButton<String>(
              tooltip: '任务选项',
              onSelected: (_) {
                store.remove(t);
                Navigator.pop(context);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('删除记录')),
              ],
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final title = Row(
                            children: [
                              Icon(kindIcon(t.config.kind), color: green),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  t.config.title,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ],
                          );
                          final status = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: t.active ? green : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                t.label,
                                style: TextStyle(
                                  color: t.active ? green : Colors.grey,
                                ),
                              ),
                            ],
                          );
                          if (constraints.maxWidth < 360) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                title,
                                const SizedBox(height: 8),
                                status,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: title),
                              const SizedBox(width: 16),
                              status,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      if (t.config.mode == 'share')
                        SelectableText('目标 ${t.config.host}:${t.config.port}')
                      else ...[
                        SelectableText(
                          '远端端口 ${t.config.port} → ${t.active ? '本机' : '原本机'} ${t.localPort > 0 ? t.localAddress : '尚未分配'}',
                        ),
                        if (t.state == 'running' && t.tunnelReady != true) ...[
                          const SizedBox(height: 8),
                          const Text(
                            '本机监听已就绪，远端连通性尚未确认。',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ],
                      if (!['running', 'sharing'].contains(t.state)) ...[
                        const SizedBox(height: 12),
                        Text(statusDescription(t)),
                      ],
                      if (t.error.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Notice(t.error, error: true),
                      ],
                      const SizedBox(height: 12),
                      const SizedBox(height: 12),
                      Text(
                        t.latencyMs == null
                            ? t.path
                            : '${t.path} · ${t.latencyMs!.toStringAsFixed(1)} ms',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: green),
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final values = <(String, String)>[
                            (
                              '运行时长',
                              '${t.duration.inMinutes} 分 ${t.duration.inSeconds % 60} 秒',
                            ),
                            if (t.config.mode == 'share')
                              ('当前连接', '${t.active ? t.clients : 0}'),
                            ('发送', formatBytes(t.up)),
                            ('接收', formatBytes(t.down)),
                          ];
                          final columns = constraints.maxWidth >= 500
                              ? values.length
                              : 2;
                          final width =
                              (constraints.maxWidth - (columns - 1) * 16) /
                              columns;
                          return Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              for (final value in values)
                                SizedBox(
                                  width: width,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        value.$1,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: Colors.grey),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        value.$2,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      if (t.active && t.stopAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text('${clockTime(t.stopAt!)} 自动停止'),
                        ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final buttons = taskActions(context, store, t);
                          if (constraints.maxWidth < 400) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final button in buttons)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: button,
                                  ),
                              ],
                            );
                          }
                          final ordered = buttons.length > 1
                              ? [
                                  buttons.last,
                                  ...buttons.skip(1).take(buttons.length - 2),
                                  buttons.first,
                                ]
                              : buttons;
                          return Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 16,
                              runSpacing: 8,
                              children: ordered,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(child: Text('连接诊断')),
                          if (t.active)
                            IconButton(
                              tooltip: t.checking ? '正在检查连接' : '检查连接',
                              onPressed: t.checking
                                  ? null
                                  : () => store.control(t, 'check'),
                              icon: t.checking
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded, size: 20),
                            ),
                          IconButton(
                            tooltip: '复制诊断（已隐藏连接凭据）',
                            onPressed: () =>
                                copy(context, diagnosticSummary(t)),
                            icon: const Icon(Icons.copy_rounded, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      info('开始时间', clockTime(t.started)),
                      if (t.ended != null) info('结束时间', clockTime(t.ended!)),
                      info('连接路径', t.path == '核心未报告连接路径' ? '路径信息暂不可用' : t.path),
                      if (t.latencyMs != null)
                        info(
                          '最近延迟',
                          '${t.latencyMs!.toStringAsFixed(1)} ms · ${t.measuredAt == null ? '' : clockTime(t.measuredAt!.toLocal())} ${t.checkFailed || DateTime.now().difference(t.measuredAt ?? t.started).inSeconds > 30 ? '（上次测量）' : ''}',
                        ),
                      if (t.relay.isNotEmpty) info('中继区域', t.relay),
                      if (t.targetReady != null) info('目标服务', targetLabel(t)),
                      if (t.diagnostic.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Notice(
                            '${t.diagnostic}${t.diagnosticAt == null || t.checking ? '' : ' · ${clockTime(t.diagnosticAt!)}'}',
                            error: t.checkFailed,
                          ),
                        ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),
                      const Text(
                        '事件记录',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (t.logs.isEmpty)
                                const Text(
                                  '暂无关键事件',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              for (final log in t.logs)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: SelectableText(
                                    log,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> taskActions(BuildContext context, Tasks store, TunnelTask t) => [
    if (t.config.mode == 'share' && t.active && t.address.isNotEmpty)
      FilledButton.icon(
        onPressed: () => shareCard(context, t),
        icon: const Icon(Icons.ios_share_rounded, size: 18),
        label: const Text('分享连接卡'),
      ),
    if (t.config.mode == 'connect' && t.active && t.localPort > 0) ...[
      if (t.config.kind == ServiceKind.web && t.state == 'running')
        FilledButton.icon(
          onPressed: () => openWeb(context, t),
          icon: const Icon(Icons.open_in_browser, size: 18),
          label: const Text('打开网页'),
        )
      else
        FilledButton.icon(
          onPressed: () => copy(context, t.localAddress),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('复制本机地址'),
        ),
      if (t.config.kind == ServiceKind.web || t.config.kind == ServiceKind.ssh)
        FilledButton.tonalIcon(
          onPressed: () => copy(
            context,
            t.config.kind == ServiceKind.ssh
                ? t.config.sshCommand(t.localPort)
                : t.localAddress,
          ),
          icon: Icon(
            t.config.kind == ServiceKind.ssh
                ? Icons.terminal
                : Icons.copy_rounded,
            size: 18,
          ),
          label: Text(
            t.config.kind == ServiceKind.ssh ? '复制 SSH 命令' : '复制本机地址',
          ),
        ),
    ],
    if (t.state == 'conflict' && t.config.mode == 'connect')
      FilledButton.icon(
        onPressed: () async {
          final retry = await store.start(t.config.copyWith(localPort: 0));
          if (context.mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute<void>(builder: (_) => TaskDetail(task: retry)),
            );
          }
        },
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('自动分配端口并重试'),
      ),
    if (!t.active)
      FilledButton.tonalIcon(
        onPressed: () => openEditor(
          context,
          connect: t.config.mode == 'connect',
          config: t.config,
        ),
        icon: const Icon(Icons.tune, size: 18),
        label: const Text('重新配置'),
      ),
    if (t.active)
      TextButton.icon(
        onPressed: t.state == 'stopping' ? null : () => store.stop(t),
        icon: const Icon(Icons.stop_circle_outlined, size: 18),
        label: Text(t.state == 'starting' ? '取消启动' : '停止任务'),
      ),
  ];

  String diagnosticSummary(TunnelTask t) => [
    'TailTap 0.1.0',
    '任务：${t.config.mode == 'share' ? '分享' : '连接'} · ${t.config.kind.label}',
    '状态：${t.label}',
    '远端端口：${t.config.port}',
    if (t.config.mode == 'connect' && t.localPort > 0) '本机监听：${t.localAddress}',
    if (t.targetReady != null) '目标服务：${targetLabel(t)}',
    '连接路径：${t.path}',
    if (t.error.isNotEmpty) '错误：${t.error}',
    ...t.logs,
  ].join('\n');
  Widget info(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelWidget = Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        );
        if (constraints.maxWidth >= 400) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 110, child: labelWidget),
              Expanded(child: SelectableText(value)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            labelWidget,
            const SizedBox(height: 4),
            SelectableText(value),
          ],
        );
      },
    ),
  );
}

class Settings extends ConsumerWidget {
  const Settings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            settingsEntry(
              context,
              icon: Icons.window_rounded,
              title: '后台运行',
              subtitle: '管理窗口关闭后的任务行为',
              page: const BackgroundSettings(),
            ),
            settingsEntry(
              context,
              icon: Icons.build_circle_outlined,
              title: '高级诊断',
              subtitle: '查看 tailcat 核心并设置桌面核心路径',
              page: const CoreSettings(),
            ),
            settingsEntry(
              context,
              icon: Icons.privacy_tip_outlined,
              title: '隐私与权限',
              subtitle: '了解相机权限与本机数据存储',
              page: const PrivacySettings(),
            ),
            settingsEntry(
              context,
              icon: Icons.info_outline_rounded,
              title: '关于',
              subtitle: 'TailTap、tailcat 上游信息和第三方许可',
              page: const AboutSettings(),
            ),
          ],
        ),
      ),
    ),
  );

  Widget settingsEntry(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget page,
  }) => Card(
    child: ListTile(
      leading: Icon(icon, color: green),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => page),
      ),
    ),
  );
}

class BackgroundSettings extends StatefulWidget {
  const BackgroundSettings({super.key});
  @override
  State<BackgroundSettings> createState() => _BackgroundSettingsState();
}

class _BackgroundSettingsState extends State<BackgroundSettings> {
  static const channel = MethodChannel('dev.tailtap/tray');
  bool keepRunning = true;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    loadSetting();
  }

  Future<void> loadSetting() async {
    if (Platform.isMacOS) {
      try {
        keepRunning =
            await channel.invokeMethod<bool>('getKeepRunning') ?? true;
      } on PlatformException {
        keepRunning = true;
      }
    }
    if (mounted) setState(() => loaded = true);
  }

  Future<void> setKeepRunning(bool value) async {
    setState(() => keepRunning = value);
    if (Platform.isMacOS) {
      await channel.invokeMethod<void>('setKeepRunning', value);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('后台运行')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (Platform.isMacOS) ...[
          formSwitch(
            title: '关闭窗口后继续运行',
            subtitle: '任务会留在菜单栏。选择“退出 TailTap”会停止全部任务。',
            value: keepRunning,
            onChanged: loaded ? setKeepRunning : null,
          ),
        ] else
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.notifications_active_outlined),
            title: Text('活动任务'),
            subtitle: Text('Android 会通过系统前台服务通知保持连接运行。'),
          ),
      ],
    ),
  );
}

class PrivacySettings extends StatelessWidget {
  const PrivacySettings({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('隐私与权限')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.qr_code_scanner_rounded),
          title: Text('相机'),
          subtitle: Text('只有打开“扫描二维码”页面时，TailTap 才会使用相机。'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.key_off_rounded),
          title: Text('连接凭据'),
          subtitle: Text('连接卡和 tailcat 原始地址不会显示在事件日志或诊断摘要中。'),
        ),
      ],
    ),
  );
}

class CoreSettings extends ConsumerStatefulWidget {
  const CoreSettings({super.key});
  @override
  ConsumerState<CoreSettings> createState() => _CoreSettingsState();
}

class _CoreSettingsState extends ConsumerState<CoreSettings> {
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
    appBar: AppBar(title: const Text('高级诊断')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.memory_rounded),
          title: Text('tailcat v0.7.0'),
          subtitle: Text('TailTap 使用 tailcat 建立加密 TCP 隧道。'),
        ),
        if (!Platform.isAndroid && !Platform.isIOS) ...[
          const SizedBox(height: 16),
          TextField(
            controller: path,
            decoration: const InputDecoration(
              labelText: 'tailcat 核心路径（可选）',
              hintText: '留空使用 TailTap 内置核心',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final store = ref.read(tasksProvider);
              store.executable = path.text.trim();
              await store.save();
              if (context.mounted) message(context, '核心路径已保存');
            },
            child: const Text('保存'),
          ),
        ],
      ],
    ),
  );
}

class AboutSettings extends StatelessWidget {
  const AboutSettings({super.key});
  Future<void> open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.hub_rounded, color: green),
          title: Text('TailTap'),
          subtitle: Text('版本 0.1.0 · 基于 tailcat 的 TCP 隧道客户端'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.code_rounded),
          title: const Text('TailTap 源码'),
          subtitle: const Text('github.com/DBinK/tailtap'),
          onTap: () => open('https://github.com/DBinK/tailtap'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.open_in_new_rounded),
          title: const Text('tailcat 上游与许可证'),
          subtitle: const Text('tailscale/tailcat · v0.7.0 · BSD-3-Clause'),
          onTap: () =>
              open('https://github.com/tailscale/tailcat/blob/v0.7.0/LICENSE'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.article_outlined),
          title: const Text('第三方开源许可'),
          subtitle: const Text('查看应用依赖和组件的许可信息'),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'TailTap',
            applicationVersion: '0.1.0',
          ),
        ),
      ],
    ),
  );
}
