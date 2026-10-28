import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/features/users/qr_layout.dart';
import 'package:moav_deploy/features/users/user_bundle_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Device feedback (iOS): the ~2 KB subscription QR rendered as a grey
/// square at a fixed 216 pt. Dense codes now grow and snap to device pixels.

String _payload(int n) => List.generate(n, (i) => 'A').join();

Future<QrImageView> _pumpQr(WidgetTester tester, String payload,
    {double width = 340, double dpr = 3}) async {
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: BundleQr(payload: payload)),
      ),
    ),
  ));
  return tester.widget<QrImageView>(find.byType(QrImageView));
}

void main() {
  group('qrGeometry', () {
    test('snaps modules to whole device pixels', () {
      final g = qrGeometry(modules: 149, maxWidth: 316, dpr: 3);
      expect(g.pixelsPerModule, 6);
      expect(g.size, closeTo(149 * 6 / 3, 1e-9));
      expect(g.size, lessThanOrEqualTo(316));
    });

    test('short codes keep the compact size', () {
      final g = qrGeometry(modules: 57, maxWidth: 316, dpr: 3);
      expect(g.size, lessThanOrEqualTo(216));
      expect(g.size, greaterThan(200));
    });

    test('never exceeds the available width', () {
      for (final dpr in [1.0, 2.0, 2.625, 3.0]) {
        for (final modules in [21, 57, 105, 149, 177]) {
          final g = qrGeometry(modules: modules, maxWidth: 280, dpr: dpr);
          expect(g.size, lessThanOrEqualTo(280), reason: '$modules @ $dpr');
          expect(g.pixelsPerModule, greaterThanOrEqualTo(1));
        }
      }
    });

    test('narrow layouts fall back gracefully', () {
      final g = qrGeometry(modules: 177, maxWidth: 100, dpr: 2);
      expect(g.pixelsPerModule, 1);
      expect(g.size, 88.5);
    });
  });

  test('long payloads trade correction for module size', () {
    expect(qrLevelFor(250), QrErrorCorrectLevel.M);
    expect(qrLevelFor(2065), QrErrorCorrectLevel.L);
  });

  test('encodeQr rejects what the validator lets through', () {
    final long = 'vless://${_payload(2900).toLowerCase()}';
    expect(encodeQr(long), isNotNull);
    final over = 'vless://${_payload(2950).toLowerCase()}';
    // qr_flutter's validator says fine; the old widget then threw in build.
    expect(QrValidator.validate(data: over).qrCode, isNotNull);
    expect(encodeQr(over), isNull);
  });

  testWidgets('a 2 KB subscription gets a wide, pixel-aligned code',
      (tester) async {
    final qr = await _pumpQr(tester, _payload(2065));
    // Version 33 at level L.
    final modules = QrCode.fromData(
      data: _payload(2065),
      errorCorrectLevel: QrErrorCorrectLevel.L,
    ).moduleCount;
    expect(modules, 149);
    expect(qr.size, greaterThan(216));
    expect(qr.size, lessThanOrEqualTo(340 - 2 * BundleQr.quietZone));
    expect((qr.size! * 3) % modules, closeTo(0, 1e-6));
    expect(qr.padding, EdgeInsets.zero);
    expect(qr.backgroundColor, Colors.white);
    expect(qr.dataModuleStyle.color, Colors.black);
    expect(qr.eyeStyle.color, Colors.black);
  });

  testWidgets('a short link keeps the compact size', (tester) async {
    final qr = await _pumpQr(tester, 'vless://${_payload(200)}');
    expect(qr.size, lessThanOrEqualTo(216));
    expect(qr.size, greaterThan(190));
  });

  testWidgets('oversized payloads still show the error state',
      (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BundleQr(payload: 'vless://${_payload(3000).toLowerCase()}')),
    ));
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Too large for a QR code'), findsOneWidget);
  });
}
