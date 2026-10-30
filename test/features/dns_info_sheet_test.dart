import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/dns_check.dart';
import 'package:moav_deploy/core/dns_records.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/features/deploy/deploy_screen.dart';
import 'package:moav_deploy/features/deploy/dns_info_sheet.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

import '../support/fake_controller.dart';
import '../support/memory_cred_store.dart';

/// The DNS info button next to the Domain field and the popup it opens:
/// records for the domain and the server's IP, copy/download of
/// dns-records.txt, and a verify step that never gates the install.

const _ip = '203.0.113.9';

class _Controller extends StubMoavController {
  _Controller({this.ipError, this.checkOutput, this.checkError});

  Object? ipError;
  String? checkOutput;
  Object? checkError;
  final checked = <(String, String)>[];
  InstallSpec? installedSpec;

  @override
  Future<String?> publicIp() async {
    if (ipError != null) throw ipError!;
    return _ip;
  }

  @override
  Future<DnsCheckReport> checkDns({
    required String domain,
    required String serverIp,
  }) async {
    checked.add((domain, serverIp));
    if (checkError != null) throw checkError!;
    final out = checkOutput ??
        'TOOL dig\nA $domain $serverIp,\nA dns.$domain $serverIp,\n'
            'NS t.$domain dns.$domain.,\nNS s.$domain dns.$domain.,\n'
            'NS m.$domain dns.$domain.,\nNS x.$domain dns.$domain.,\n';
    return DnsCheck.parse(out, domain: domain, serverIp: serverIp);
  }

  @override
  Future<InstallHandle> install(InstallSpec spec) async {
    installedSpec = spec;
    return const InstallHandle(jobId: '1', logPath: '.moav-deploy/deploy.log');
  }

  @override
  Future<InstallStatus> installStatus(InstallHandle handle) async =>
      const InstallStatus(phase: InstallPhase.succeeded, progress: 1);
}

class _Sharer extends DnsZoneSharer {
  const _Sharer(this.shared);

  final List<(String, String)> shared;

  @override
  Future<void> share(String text, {required String domain, Rect? origin}) async {
    shared.add((domain, text));
  }
}

Future<_Controller> _pump(
  WidgetTester tester, {
  _Controller? controller,
  List<(String, String)>? shared,
  ServerProfile profile = demoProfile,
}) async {
  final c = controller ?? _Controller();
  await tester.pumpWidget(ProviderScope(
    retry: noProviderRetry,
    overrides: [
      secureCredStoreProvider.overrideWithValue(MemoryCredStore()),
      moavControllerProvider(profile.id).overrideWithValue(c),
      if (shared != null)
        dnsZoneSharerProvider.overrideWithValue(_Sharer(shared)),
    ],
    child: MaterialApp(
      theme: moavDarkTheme(),
      home: DeployScreen(profile: profile),
    ),
  ));
  await tester.pumpAndSettle();
  return c;
}

Finder _field(String label) => find.widgetWithText(TextField, label);

IconButton _infoButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(const ValueKey('dns-info')));

Future<void> _openSheet(WidgetTester tester, {String domain = 'vpn.example.org'}) async {
  await tester.enterText(_field('Domain'), domain);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('dns-info')));
  await tester.pumpAndSettle();
}

/// Scrolls the sheet's own list until [f] is built; negative [delta]
/// scrolls back up.
Future<void> _reveal(WidgetTester tester, Finder f, {double delta = 120}) async {
  final list = find.descendant(
    of: find.byType(DnsInfoSheet),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(f, delta, scrollable: list.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('info button is disabled without a domain and enabled with one',
      (tester) async {
    await _pump(tester);
    expect(_infoButton(tester).onPressed, isNull);
    await tester.enterText(_field('Domain'), 'vpn.example.org');
    await tester.pumpAndSettle();
    expect(_infoButton(tester).onPressed, isNotNull);
    expect(find.textContaining('Tap the info button'), findsOneWidget);
    await tester.enterText(_field('Domain'), '');
    await tester.pumpAndSettle();
    expect(_infoButton(tester).onPressed, isNull);
  });

  testWidgets('sheet shows the server IP and the six records for the domain',
      (tester) async {
    await _pump(tester);
    await _openSheet(tester, domain: ' VPN.Example.org ');
    expect(find.text('DNS records'), findsOneWidget);
    expect(find.text('vpn.example.org'), findsWidgets);
    expect(find.byKey(const ValueKey('dns-server-ip')), findsOneWidget);
    expect(find.text(_ip), findsWidgets);
    for (final r in DnsRecords.forDomain('vpn.example.org', _ip)) {
      final row = find.byKey(ValueKey('dns-record-${r.type}-${r.name}'));
      await _reveal(tester, row);
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text(r.name)),
        findsOneWidget,
      );
    }
    expect(find.text('OPT-IN'), findsOneWidget);
    await _reveal(tester, find.byType(CodeBlock));
    final code = tester.widget<CodeBlock>(find.byType(CodeBlock));
    expect(code.text, contains('vpn.example.org.\t1\tIN\tA\t$_ip'));
    expect(code.text, contains(';; MoaV DNS Records for vpn.example.org'));
  });

  testWidgets('verify reports each record and the summary', (tester) async {
    final c = await _pump(tester);
    await _openSheet(tester);
    await _reveal(tester, find.byKey(const ValueKey('dns-verify')));
    await tester.tap(find.byKey(const ValueKey('dns-verify')));
    await tester.pumpAndSettle();
    expect(c.checked, [('vpn.example.org', _ip)]);
    await _reveal(tester, find.byKey(const ValueKey('dns-report')));
    expect(find.text('All 6 records resolve as expected.'), findsOneWidget);
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('Checked from the server with dig.'), findsOneWidget);
    await _reveal(tester, find.byKey(const ValueKey('dns-verify')), delta: -120);
    expect(find.text('Verify again'), findsOneWidget);
    await _reveal(tester, find.byKey(const ValueKey('dns-record-A-vpn.example.org')), delta: -120);
    expect(find.text('PASS'), findsWidgets);
    expect(find.text('points to $_ip'), findsNWidgets(2));
  });

  testWidgets('verify shows failures without blocking anything', (tester) async {
    final c = _Controller(
      checkOutput: 'TOOL host\nA vpn.example.org 198.51.100.1,\n'
          'A dns.vpn.example.org \nNS t.vpn.example.org dns.vpn.example.org.,\n'
          'NS s.vpn.example.org \nNS m.vpn.example.org dns.vpn.example.org.,\n'
          'NS x.vpn.example.org \n',
    );
    await _pump(tester, controller: c);
    await _openSheet(tester);
    await _reveal(tester, find.byKey(const ValueKey('dns-verify')));
    await tester.tap(find.byKey(const ValueKey('dns-verify')));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const ValueKey('dns-report')));
    expect(find.textContaining('3 of 6 records need attention'), findsOneWidget);
    await _reveal(tester, find.byKey(const ValueKey('dns-record-A-vpn.example.org')), delta: -120);
    expect(find.text('points to 198.51.100.1'), findsOneWidget);
    expect(find.text('does not resolve'), findsOneWidget);
    expect(find.text('no NS delegation'), findsNWidgets(2));
    expect(find.text('WARN'), findsOneWidget, reason: 'x is opt-in');
    expect(find.text('FAIL'), findsAtLeastNWidgets(3));
  });

  testWidgets('no DNS tool on the server is reported, not thrown', (tester) async {
    await _pump(tester, controller: _Controller(checkOutput: 'TOOL none\n'));
    await _openSheet(tester);
    await _reveal(tester, find.byKey(const ValueKey('dns-verify')));
    await tester.tap(find.byKey(const ValueKey('dns-verify')));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const ValueKey('dns-report')));
    expect(find.textContaining('no dig, host or nslookup'), findsOneWidget);
    expect(find.text('SKIP'), findsWidgets);
  });

  testWidgets('a failed check shows an error banner and keeps the sheet usable',
      (tester) async {
    final c = _Controller(checkError: StateError('connection dropped'));
    await _pump(tester, controller: c);
    await _openSheet(tester);
    await _reveal(tester, find.byKey(const ValueKey('dns-verify')));
    await tester.tap(find.byKey(const ValueKey('dns-verify')));
    await tester.pumpAndSettle();
    expect(find.textContaining('connection dropped'), findsOneWidget);
    expect(find.byKey(const ValueKey('dns-report')), findsNothing);
    c.checkError = null;
    await tester.tap(find.byKey(const ValueKey('dns-verify')));
    await tester.pumpAndSettle();
    expect(find.textContaining('connection dropped'), findsNothing);
    await _reveal(tester, find.byKey(const ValueKey('dns-report')));
    expect(find.text('All 6 records resolve as expected.'), findsOneWidget);
  });

  testWidgets('copy puts the zone text on the clipboard', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await _pump(tester);
    await _openSheet(tester);
    await _reveal(tester, find.byKey(const ValueKey('dns-copy')));
    await tester.tap(find.byKey(const ValueKey('dns-copy')));
    await tester.pumpAndSettle();
    expect(copied, hasLength(1));
    expect(copied.single, contains('dns.vpn.example.org.\t1\tIN\tA\t$_ip'));
    expect(find.text('DNS records copied'), findsOneWidget);
  });

  testWidgets('download hands dns-records.txt to the share sheet', (tester) async {
    final shared = <(String, String)>[];
    await _pump(tester, shared: shared);
    await _openSheet(tester);
    await _reveal(tester, find.byKey(const ValueKey('dns-download')));
    await tester.tap(find.byKey(const ValueKey('dns-download')));
    await tester.pumpAndSettle();
    expect(shared, hasLength(1));
    expect(shared.single.$1, 'vpn.example.org');
    expect(shared.single.$2, contains('x.vpn.example.org.\t1\tIN\tNS\tdns.vpn.example.org.'));
    expect(DnsRecords.fileName, 'dns-records.txt');
  });

  testWidgets('when the server cannot report its IP the sheet offers a retry',
      (tester) async {
    final c = _Controller(ipError: StateError('ssh down'));
    await _pump(tester, controller: c);
    await _openSheet(tester);
    expect(find.byKey(const ValueKey('dns-server-ip')), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('SERVER_IP'), findsWidgets);
    await _reveal(tester, find.byKey(const ValueKey('dns-verify')));
    expect(
      tester.widget<GradientButton>(find.byKey(const ValueKey('dns-verify'))).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.byKey(const ValueKey('dns-copy'))).onPressed,
      isNull,
    );
    expect(find.byType(CodeBlock), findsNothing, reason: 'no zone without an IP');
    c.ipError = null;
    await _reveal(tester, find.text('Try again'), delta: -120);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dns-server-ip')), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a profile addressed by IP uses that IP when SSH is down',
      (tester) async {
    const byIp = ServerProfile(
      id: 's1',
      label: 'Demo',
      host: '198.51.100.4',
      port: 22,
      username: 'root',
      authMethod: SshAuthMethod.importedKey,
    );
    await _pump(
      tester,
      controller: _Controller(ipError: StateError('ssh down')),
      profile: byIp,
    );
    await _openSheet(tester);
    expect(find.text('198.51.100.4'), findsWidgets);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('the install starts without ever opening or verifying DNS',
      (tester) async {
    final c = await _pump(tester);
    await tester.enterText(_field('Domain'), 'vpn.example.org');
    await tester.enterText(_field('Admin dashboard password'), 'correct-horse-battery');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Start install'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Start install'));
    await tester.pumpAndSettle();
    expect(c.installedSpec?.domain, 'vpn.example.org');
    expect(c.checked, isEmpty);
  });

  testWidgets('closing the sheet leaves the form intact and startable',
      (tester) async {
    final c = await _pump(tester);
    await _openSheet(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(DnsInfoSheet), findsNothing);
    expect(tester.widget<TextField>(_field('Domain')).controller?.text,
        'vpn.example.org');
    await tester.enterText(_field('Admin dashboard password'), 'correct-horse-battery');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Start install'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Start install'));
    await tester.pumpAndSettle();
    expect(c.installedSpec?.domain, 'vpn.example.org');
  });
}
