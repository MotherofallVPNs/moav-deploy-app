import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/features/users/bundle_share.dart';
import 'package:moav_deploy/features/users/user_bundle_screen.dart';
import 'package:moav_deploy/features/users/user_detail_screen.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/widgets/brand_icon.dart';

import '../support/fake_controller.dart';
import '../support/memory_cred_store.dart';

/// UI polish: brand marks in the menu, "Share .zip" for a user's bundle, and
/// the admin dashboard gone from the server hub (still on the Server tab).

final _serverZip = ZipEncoder().encodeBytes(Archive()
  ..add(ArchiveFile.string('README.html', '<html>'))
  ..add(ArchiveFile.string('reality.txt', 'vless://alice@h:443\n')));

class _Controller extends StubMoavController {
  _Controller({this.serverZip});

  /// What the box answers for the archive; `null` means "no zip here".
  final Uint8List? serverZip;
  var archiveCalls = 0;

  @override
  Future<List<MoavUser>> listUsers() async =>
      const [MoavUser(name: 'alice', bundleReady: true, protocols: ['xray'])];

  @override
  Future<ServiceFlags> serviceFlags() async =>
      ServiceFlags(values: const {}, collectedAt: DateTime(2026));

  @override
  Future<Bundle> getBundle(String user) async => Bundle(
        user: user,
        fetchedAt: DateTime(2026),
        path: '/opt/moav/outputs/bundles/$user',
        entries: const [
          BundleEntry(
            protocol: 'subscription',
            fileName: 'subscription.txt',
            content: 'https://h/sub/alice\n',
            qrPayload: 'https://h/sub/alice',
          ),
          BundleEntry(
            protocol: 'reality',
            fileName: 'reality.txt',
            content: 'vless://alice@h:443\n',
            qrPayload: 'vless://alice@h:443',
          ),
          BundleEntry(
            protocol: 'trusttunnel',
            fileName: 'trusttunnel.toml',
            content: '# tt\n',
          ),
        ],
      );

  @override
  Future<Uint8List?> getBundleArchive(String user) async {
    archiveCalls++;
    return serverZip;
  }
}

class _RecordingSharer extends BundleZipSharer {
  final shared = <(String fileName, Uint8List bytes, String user, Rect? origin)>[];

  @override
  Future<void> share(
    String fileName,
    Uint8List bytes, {
    required String user,
    Rect? origin,
  }) async {
    shared.add((fileName, bytes, user, origin));
  }
}

Widget _app(_Controller controller, _RecordingSharer sharer) => ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(
            MemoryCredStore()..profiles = [demoProfile]),
        moavControllerFactoryProvider
            .overrideWithValue(FakeControllerFactory(controller)),
        bundleZipSharerProvider.overrideWithValue(sharer),
      ],
      child: const MoavDeployApp(lockEnabled: false),
    );

Future<void> _openAlice(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Demo'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Users'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('alice'));
  await tester.pumpAndSettle();
  expect(find.byType(UserDetailScreen), findsOneWidget);
}

List<String> _names(Uint8List zip) =>
    ZipDecoder().decodeBytes(zip).files.map((f) => f.name).toList();

void main() {
  testWidgets('menu social row draws the GitHub, X and Telegram marks',
      (tester) async {
    await tester.pumpWidget(_app(_Controller(), _RecordingSharer()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    for (final (tooltip, asset) in [
      ('GitHub', BrandIcon.github),
      ('X', BrandIcon.x),
      ('Telegram', BrandIcon.telegram),
    ]) {
      final icon = find.descendant(
          of: find.byTooltip(tooltip), matching: find.byType(BrandIcon));
      expect(icon, findsOneWidget);
      expect(tester.widget<BrandIcon>(icon).asset, asset);
    }
    expect(find.byType(SvgPicture), findsNWidgets(3));
    // Tinted like the other rows' icons, so the marks follow the theme.
    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture).first);
    final tint = IconTheme.of(tester.element(find.byType(BrandIcon).first)).color;
    expect(svg.colorFilter, ColorFilter.mode(tint!, BlendMode.srcIn));
    // Drawn at the app's icon size, so the row matches the other entries.
    for (final icon in find.byType(BrandIcon).evaluate()) {
      expect(icon.size, const Size(22, 22));
    }
  });

  testWidgets('server hub has no Admin dashboard tile; Server tab still does',
      (tester) async {
    await tester.pumpWidget(_app(_Controller(), _RecordingSharer()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();

    expect(find.text('Server info'), findsOneWidget);
    // The hub list is lazy: scroll to the end so every tile has been built.
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.text('Deploy'), findsOneWidget);
    expect(find.text('Grafana'), findsOneWidget);
    expect(find.text('Admin dashboard'), findsNothing);
  });

  testWidgets('Share .zip on the detail page shares the server-built archive',
      (tester) async {
    final controller = _Controller(serverZip: _serverZip);
    final sharer = _RecordingSharer();
    await tester.pumpWidget(_app(controller, sharer));
    await _openAlice(tester);

    // The per-config share is still there; the zip sits next to it.
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(find.text('Download connection bundle'), findsOneWidget);
    await tester.ensureVisible(find.text('Share .zip'));
    await tester.tap(find.text('Share .zip'));
    await tester.pumpAndSettle();

    expect(controller.archiveCalls, 1);
    final (name, bytes, user, origin) = sharer.shared.single;
    expect(name, 'alice-moav-bundle.zip');
    expect(user, 'alice');
    expect(bytes, _serverZip);
    expect(_names(bytes), ['README.html', 'reality.txt']);
    expect(origin, isNotNull);
  });

  testWidgets('Share .zip on the bundle screen zips the fetched configs when '
      'the box cannot', (tester) async {
    final controller = _Controller();
    final sharer = _RecordingSharer();
    await tester.pumpWidget(_app(controller, sharer));
    await _openAlice(tester);
    await tester.tap(find.text('Download connection bundle'));
    await tester.pumpAndSettle();
    expect(find.byType(UserBundleScreen), findsOneWidget);

    // Every config keeps its own share; the zip is an extra app bar action.
    expect(find.byTooltip('Share'), findsWidgets);
    await tester.tap(find.byTooltip('Share .zip'));
    await tester.pumpAndSettle();

    expect(controller.archiveCalls, 1);
    final (name, bytes, _, _) = sharer.shared.single;
    expect(name, 'alice-moav-bundle.zip');
    expect(_names(bytes), ['subscription.txt', 'reality.txt', 'trusttunnel.toml']);
    expect(find.textContaining('Zipped the fetched configs'), findsOneWidget);
  });
}
