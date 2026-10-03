import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tail_tap/core/tasks.dart';
import 'package:tail_tap/main.dart';
import 'package:tail_tap/models/connection.dart';

// Regenerate with TAILTAP_SCREENSHOT_FONT=/path/to/a/Chinese/font.ttf
// flutter test test/screenshots_test.dart. Uses nonfunctional example credentials.
void main() {
  final fontPath = Platform.environment['TAILTAP_SCREENSHOT_FONT'];
  testWidgets('Render README screenshots from application widgets', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final font = FontLoader('Roboto')
      ..addFont(
        Future.value(ByteData.sublistView(File(fontPath!).readAsBytesSync())),
      );
    await font.load();
    await (FontLoader('monospace')..addFont(
          Future.value(ByteData.sublistView(File(fontPath).readAsBytesSync())),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const shareConfig = ConnectionConfig(
      mode: 'share',
      kind: ServiceKind.ssh,
      port: 22,
    );
    const connectConfig = ConnectionConfig(
      mode: 'connect',
      kind: ServiceKind.ssh,
      port: 22,
      address: 'tcREADMEExampleNotARealConnection',
      localPort: 2222,
    );
    for (final layout in ['mobile', 'desktop']) {
      tester.view.physicalSize = layout == 'mobile'
          ? const Size(390, 1000)
          : const Size(1200, 900);
      for (final page in [
        'home',
        'detail-share',
        'detail-connect',
        'share',
        'connect',
        'connection-card',
      ]) {
        final store = Tasks();
        final share = TunnelTask('example-share', shareConfig)
          ..state = 'sharing'
          ..address = connectConfig.address
          ..targetReady = true
          ..clients = 1
          ..up = 24576
          ..down = 12288;
        final connection = TunnelTask('example-connect', connectConfig)
          ..state = 'running'
          ..localPort = 2222
          ..tunnelReady = true
          ..up = 12288
          ..down = 24576;
        store.tasks.add(share);
        store.recent.add(shareConfig);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [tasksProvider.overrideWith((ref) => store)],
            child: RepaintBoundary(key: boundary, child: const MyApp()),
          ),
        );
        await tester.pumpAndSettle();
        final destination = switch (page) {
          'detail-share' => TaskDetail(task: share),
          'detail-connect' => TaskDetail(task: connection),
          'share' => const ServiceEditor(connect: false, initial: shareConfig),
          'connect' => const ServiceEditor(
            connect: true,
            initial: connectConfig,
          ),
          _ => null,
        };
        if (destination != null) {
          navigatorKey.currentState!.push(
            MaterialPageRoute<void>(builder: (_) => destination),
          );
          await tester.pumpAndSettle();
        }
        if (page == 'connection-card') {
          // The modal is rendered by the same entry point used by running tasks.
          shareCard(navigatorKey.currentContext!, share);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        final render =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ImageByteFormat.png);
          await File('docs/screenshots/$page-$layout.png')
              .writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    }
  }, skip: fontPath == null);
}
