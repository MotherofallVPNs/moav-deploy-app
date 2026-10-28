import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_identity.dart';
import 'package:moav_deploy/features/about/about_screen.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

/// Issue #25: About screen with version, signing fingerprint and the
/// SHA256SUMS verification note.

const _fingerprint =
    '0F:1E:2D:3C:4B:5A:69:78:87:96:A5:B4:C3:D2:E1:F0:'
    '00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF';

Widget _screen(AppIdentity identity) => ProviderScope(
      overrides: [
        appIdentityProvider.overrideWith((_) async => identity),
      ],
      child: MaterialApp(theme: moavDarkTheme(), home: const AboutScreen()),
    );

const _identity = AppIdentity(
  appName: 'MoaV Deploy',
  version: '0.2.7',
  buildNumber: '10',
  signingFingerprints: [_fingerprint],
);

void main() {
  // A phone-height viewport so the whole page is laid out without scrolling.
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(480, 2400);
    view.devicePixelRatio = 1;
    addTearDown(view.reset);
  });

  testWidgets('shows name, version (build) and the runtime fingerprint',
      (tester) async {
    await tester.pumpWidget(_screen(_identity));
    await tester.pumpAndSettle();

    expect(find.text('Deploy'), findsOneWidget);
    expect(find.text('Version 0.2.7 (10)'), findsOneWidget);
    // Fingerprint is shown as four lines of eight bytes.
    expect(find.text('0F:1E:2D:3C:4B:5A:69:78\n'
        '87:96:A5:B4:C3:D2:E1:F0\n'
        '00:11:22:33:44:55:66:77\n'
        '88:99:AA:BB:CC:DD:EE:FF'), findsOneWidget);
    expect(find.text('SIGNING CERTIFICATE'), findsOneWidget);
    expect(find.textContaining('read from the system at runtime'),
        findsOneWidget);
  });

  testWidgets('copies the one-line fingerprint', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(_screen(_identity));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy fingerprint'));
    await tester.pumpAndSettle();

    final copy = calls.singleWhere((c) => c.method == 'Clipboard.setData');
    expect(copy.arguments, {'text': _fingerprint});
    expect(find.text('Fingerprint copied'), findsOneWidget);
  });

  testWidgets('explains the SHA256SUMS check and links out', (tester) async {
    await tester.pumpWidget(_screen(_identity));
    await tester.pumpAndSettle();

    expect(find.text('VERIFY YOUR DOWNLOAD'), findsOneWidget);
    expect(find.textContaining('SHA256SUMS file'), findsOneWidget);
    expect(
      find.textContaining('sha256sum --ignore-missing -c SHA256SUMS'),
      findsOneWidget,
    );
    expect(find.textContaining('app-release.apk: OK'), findsOneWidget);
    expect(find.text('Source code'), findsOneWidget);
    expect(find.text('github.com/MotherofallVPNs/moav-deploy-app'),
        findsOneWidget);
    expect(find.text('Releases'), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);
  });

  testWidgets('licenses row opens the Flutter license page with the version',
      (tester) async {
    await tester.pumpWidget(_screen(_identity));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open-source licenses'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('MoaV Deploy'), findsWidgets);
    expect(find.text('0.2.7 (10)'), findsOneWidget);
  });

  testWidgets('without a signing API the card says so and hides Copy',
      (tester) async {
    await tester.pumpWidget(_screen(const AppIdentity(
      appName: 'MoaV Deploy',
      version: '0.2.7',
      buildNumber: '10',
      signingFingerprints: [],
    )));
    await tester.pumpAndSettle();

    expect(find.text(AboutScreen.noFingerprint), findsOneWidget);
    expect(find.text('Copy fingerprint'), findsNothing);
    expect(find.text('Version 0.2.7 (10)'), findsOneWidget);
  });
}
