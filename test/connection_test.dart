import 'package:flutter_test/flutter_test.dart';
import 'package:tail_tap/models/connection.dart';

void main() {
  test('SSH username survives card and stored configuration', () {
    const config = ConnectionConfig(
      mode: 'share',
      kind: ServiceKind.ssh,
      port: 22,
      sshUser: 'binn',
    );
    final received = ConnectionConfig.parse(
      config.card('tcABCDEFGHIJKLMNOPQRSTUV'),
    );
    expect(received.sshUser, 'binn');
    expect(
      received.copyWith(localPort: 2222).sshCommand(2222),
      "ssh -p 2222 'binn@127.0.0.1'",
    );
    expect(ConnectionConfig.fromJson(config.toJson()).sshUser, 'binn');
    expect(ConnectionConfig.validSshUser('user; touch /tmp/file'), isFalse);
    expect(ConnectionConfig.validSshUser('-oProxyCommand'), isFalse);
    expect(ConnectionConfig.validSshUser('binn'), isTrue);
  });
  const addr = 'tcomFwWCCcjS5nKNqAod034nWoJZW0LZqDhhC8U_dKdnDRYQ8uNGFpGQEu';
  test('connection card round trips Unicode names and HTTPS paths', () {
    const config = ConnectionConfig(
      mode: 'share',
      kind: ServiceKind.web,
      port: 8443,
      name: '开发网页 & docs',
      webScheme: 'https',
      webPath: '/docs',
    );
    final parsed = ConnectionConfig.parse(config.card(addr));
    expect(parsed.address, addr);
    expect(parsed.name, config.name);
    expect(parsed.port, 8443);
    expect(parsed.kind, ServiceKind.web);
    expect(parsed.webScheme, 'https');
    expect(parsed.webPath, '/docs');
    expect(parsed.localPort, 0);
  });
  test('raw address requires an explicit remote port', () {
    expect(ConnectionConfig.parse(addr).port, 0);
  });
  test('forward commands accept copied HTML whitespace and validate ports', () {
    final parsed = ConnectionConfig.parse('tailcat forward $addr 22&#x20;');
    expect(parsed.address, addr);
    expect(parsed.port, 22);
    expect(parsed.localPort, 0);
    expect(
      () => ConnectionConfig.parse('tailcat forward $addr 0'),
      throwsFormatException,
    );
    expect(
      () => ConnectionConfig.parse('tailcat forward $addr 65536'),
      throwsFormatException,
    );
    expect(
      () => ConnectionConfig.parse('tailcat forward $addr 22; echo unsafe'),
      throwsFormatException,
    );
  });
  test('unknown versions and invalid metadata are rejected', () {
    final card = const ConnectionConfig(
      mode: 'share',
      kind: ServiceKind.port,
      port: 80,
    ).card(addr);
    for (final input in [
      card.replaceFirst('v=1', 'v=2'),
      card.replaceFirst('port=80', 'port=65536'),
      card.replaceFirst('kind=port', 'kind=exec'),
      'https://example.com',
    ]) {
      expect(() => ConnectionConfig.parse(input), throwsFormatException);
    }
  });
  test('browser path cannot redirect to an external host', () {
    final card = const ConnectionConfig(
      mode: 'share',
      kind: ServiceKind.web,
      port: 80,
      webPath: '//evil.example',
    ).card(addr);
    expect(() => ConnectionConfig.parse(card), throwsFormatException);
  });
}
