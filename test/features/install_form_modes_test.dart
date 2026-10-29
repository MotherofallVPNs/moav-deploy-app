import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/moav_services.dart';
import 'package:moav_deploy/features/deploy/deploy_screen.dart';
import 'package:moav_deploy/features/deploy/install_inputs.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

import '../support/fake_controller.dart';
import '../support/memory_cred_store.dart';

/// The install form: two fields by default (domain, admin password with a
/// random generator); email, branch and services behind "Advanced".

class _Controller extends StubMoavController {
  InstallSpec? installedSpec;

  @override
  Future<InstallHandle> install(InstallSpec spec) async {
    installedSpec = spec;
    return const InstallHandle(jobId: '1', logPath: '.moav-deploy/deploy.log');
  }

  @override
  Future<InstallStatus> installStatus(InstallHandle handle) async =>
      const InstallStatus(phase: InstallPhase.succeeded, progress: 1);
}

Future<_Controller> _pump(WidgetTester tester) async {
  final c = _Controller();
  await tester.pumpWidget(ProviderScope(
    retry: noProviderRetry,
    overrides: [
      secureCredStoreProvider.overrideWithValue(MemoryCredStore()),
      moavControllerProvider(demoProfile.id).overrideWithValue(c),
    ],
    child: MaterialApp(
      theme: moavDarkTheme(),
      home: const DeployScreen(profile: demoProfile),
    ),
  ));
  await tester.pumpAndSettle();
  return c;
}

Finder _field(String label) => find.widgetWithText(TextField, label);

/// Scrolls the form until [f] is built; negative [delta] scrolls back up.
Future<void> _show(WidgetTester tester, Finder f, {double delta = 150}) async {
  await tester.scrollUntilVisible(f, delta, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> _start(WidgetTester tester) async {
  await _show(tester, find.text('Start install'));
  await tester.tap(find.text('Start install'));
  await tester.pumpAndSettle();
}

void main() {
  group('InstallInputs', () {
    test('generated passwords pass the installer rules and vary', () {
      final a = InstallInputs.generatePassword();
      final b = InstallInputs.generatePassword();
      expect(a.length, InstallInputs.generatedLength);
      expect(a, isNot(b));
      expect(a, matches(RegExp(r'^[A-Za-z0-9]+$')));
      expect(a, isNot(matches(RegExp('["\'\\\\\$`#\\s]'))));
      // Look-alikes are left out so the password can be read off a screen.
      expect(InstallInputs.passwordAlphabet, isNot(contains('0')));
      expect(InstallInputs.passwordAlphabet, isNot(contains('O')));
      expect(InstallInputs.passwordAlphabet, isNot(contains('l')));
      expect(InstallInputs.passwordAlphabet, isNot(contains('I')));
      expect(InstallInputs.passwordAlphabet, isNot(contains('1')));
    });

    test('a seeded generator is deterministic', () {
      expect(
        InstallInputs.generatePassword(random: Random(7)),
        InstallInputs.generatePassword(random: Random(7)),
      );
    });

    test('the default email is info@ the domain, none without one', () {
      expect(InstallInputs.defaultEmail(' vpn.example.org '), 'info@vpn.example.org');
      expect(InstallInputs.defaultEmail(''), '');
      expect(InstallInputs.defaultEmail('   '), '');
    });
  });

  testWidgets('simplified view: domain and password only, advanced hidden',
      (tester) async {
    await _pump(tester);
    expect(_field('Domain'), findsOneWidget);
    expect(_field('Admin dashboard password'), findsOneWidget);
    expect(find.text('Generate random'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.textContaining('domainless'), findsOneWidget);
    expect(_field("Let's Encrypt email"), findsNothing);
    expect(_field('MoaV branch'), findsNothing);
    expect(find.text('SERVICES'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('one-tap domainless install with the default services',
      (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.text('Generate random'));
    await tester.pumpAndSettle();
    final password =
        tester.widget<TextField>(_field('Admin dashboard password')).controller!.text;
    expect(password.length, InstallInputs.generatedLength);
    // Generated passwords are revealed so they can be written down.
    expect(tester.widget<TextField>(_field('Admin dashboard password')).obscureText,
        isFalse);
    expect(find.text('At least 12 characters'), findsNothing);

    await _start(tester);
    final spec = c.installedSpec;
    expect(spec, isNotNull);
    expect(spec!.domain, '');
    expect(spec.email, '');
    expect(spec.adminPassword, password);
    expect(spec.extraEnv, isEmpty);
    expect(spec.profiles, MoavProfiles.defaults);
  });

  testWidgets('the password can be hidden again and typed by hand',
      (tester) async {
    await _pump(tester);
    expect(tester.widget<TextField>(_field('Admin dashboard password')).obscureText,
        isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_field('Admin dashboard password')).obscureText,
        isFalse);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_field('Admin dashboard password')).obscureText,
        isTrue);
    await tester.enterText(_field('Admin dashboard password'), 'short');
    await tester.pumpAndSettle();
    expect(find.text('At least 12 characters'), findsOneWidget);
  });

  testWidgets('advanced reveals email prefilled from the domain, branch and services',
      (tester) async {
    final c = await _pump(tester);
    await tester.enterText(_field('Domain'), 'vpn.example.org');
    await tester.pumpAndSettle();
    expect(find.textContaining('domainless'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('advanced-toggle')));
    await tester.pumpAndSettle();

    final email = tester.widget<TextField>(_field("Let's Encrypt email"));
    expect(email.controller!.text, 'info@vpn.example.org');
    final branch = tester.widget<TextField>(_field('MoaV branch'));
    expect(branch.decoration!.hintText, 'main');
    expect(branch.controller!.text, '');
    await _show(tester, find.text('SERVICES'));
    expect(find.byType(CheckboxListTile), findsNWidgets(MoavProfiles.all.length));

    // The email keeps following the domain until it is edited by hand.
    await _show(tester, _field('Domain'), delta: -150);
    await tester.enterText(_field('Domain'), 'edge.example.net');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_field("Let's Encrypt email")).controller!.text,
        'info@edge.example.net');
    await tester.enterText(_field("Let's Encrypt email"), 'ops@example.net');
    await tester.enterText(_field('Domain'), 'vpn.example.org');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_field("Let's Encrypt email")).controller!.text,
        'ops@example.net');

    await tester.enterText(_field('MoaV branch'), 'dev');
    await tester.enterText(_field('Admin dashboard password'), 'secret-but-long');
    await _start(tester);
    final spec = c.installedSpec!;
    expect(spec.domain, 'vpn.example.org');
    expect(spec.email, 'ops@example.net');
    expect(spec.extraEnv, {'MOAV_BRANCH': 'dev'});
  });

  testWidgets('a domain without opening Advanced still gets info@ as the email',
      (tester) async {
    final c = await _pump(tester);
    await tester.enterText(_field('Domain'), 'vpn.example.org');
    await tester.enterText(_field('Admin dashboard password'), 'secret-but-long');
    await _start(tester);
    expect(c.installedSpec!.email, 'info@vpn.example.org');
  });

  testWidgets('the Advanced row itself toggles the switch', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(_field("Let's Encrypt email"), findsOneWidget);
    expect(tester.widget<Switch>(find.byKey(const ValueKey('advanced-toggle'))).value,
        isTrue);
  });
}
