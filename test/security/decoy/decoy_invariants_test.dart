import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/features/notes/notes_app.dart';
import 'package:moav_deploy/features/notes/notes_store.dart';
import 'package:moav_deploy/features/servers/servers_home_screen.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/security/app_lock.dart';
import 'package:moav_deploy/security/app_log.dart';
import 'package:moav_deploy/security/decoy/decoy_config.dart';
import 'package:moav_deploy/security/decoy/decoy_identity.dart';
import 'package:moav_deploy/security/decoy/decoy_pin.dart';
import 'package:moav_deploy/security/decoy/decoy_provider.dart';
import 'package:moav_deploy/security/onboarding.dart';
import 'package:moav_deploy/theme/moav_theme.dart';

import '../../support/fake_controller.dart';
import '../../support/fake_decoy_identity.dart';
import '../../support/fake_lock.dart';
import '../../support/memory_cred_store.dart';

/// Leak-prevention invariants of disguise mode (issue #15): the Notes decoy
/// is built from nothing that knows about servers or keys, a disguised
/// launch with saved servers shows none of them, and the passcode itself
/// never reaches storage or a log line.
const _fast = 1000;
const _pin = '2580';
const _pem = '-----BEGIN OPENSSH PRIVATE KEY-----\n'
    'b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW\n'
    '-----END OPENSSH PRIVATE KEY-----\n';

void main() {
  group('source', () {
    final notesDir = Directory('lib/features/notes');
    final files = notesDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('the Notes decoy imports only Flutter, its store and the decoy gate',
        () {
      expect(files, isNotEmpty);
      const allowed = [
        'dart:',
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:path_provider/',
        '../../security/decoy/',
        '../../security/app_log.dart',
        'notes_store.dart',
      ];
      for (final f in files) {
        final imports = RegExp(r"^import '([^']+)';", multiLine: true)
            .allMatches(f.readAsStringSync())
            .map((m) => m.group(1)!);
        for (final i in imports) {
          expect(allowed.any(i.startsWith), isTrue,
              reason: '${f.path} imports $i');
        }
      }
    });

    test('nothing in the decoy names the secure store, servers or brand', () {
      const forbidden = [
        'SecureCredStore',
        'secureCredStoreProvider',
        'serversProvider',
        'moavControllerProvider',
        'MoavColors',
        'moavDarkTheme',
        'MoavMark',
        'JetBrains',
        'Inter',
        'ServerProfile',
      ];
      for (final f in files) {
        final src = f.readAsStringSync();
        for (final word in forbidden) {
          expect(src, isNot(contains(word)), reason: '${f.path} mentions $word');
        }
      }
    });
  });

  test('the Notes theme carries no MoaV font or colour', () {
    for (final b in Brightness.values) {
      final t = notesTheme(b);
      final family = t.textTheme.bodyMedium?.fontFamily ?? '';
      expect(family, isNot(contains('Inter')));
      expect(family, isNot(contains('JetBrains')));
      expect(t.colorScheme.primary, isNot(MoavColors.cyan));
      expect(t.scaffoldBackgroundColor,
          b == Brightness.light ? NotesColors.paper : NotesColors.paperDark);
    }
  });

  testWidgets('a disguised launch with saved servers shows none of them',
      (tester) async {
    final d = await DecoyPin.hash(_pin, iterations: _fast);
    final boot = DecoyConfig(
      enabled: true,
      pinHash: d.hash,
      salt: d.salt,
      iterations: _fast,
    );
    final store = MemoryCredStore()
      ..profiles = [demoProfile]
      ..secrets['s1'] = _pem
      ..decoy = boot.toJson();
    final notes = MemoryNotesStore()
      ..notes = [
        Note(id: '1', title: 'Groceries', body: 'milk', updatedAt: DateTime(2026)),
      ];
    final lock = GatedLock();
    await tester.pumpWidget(ProviderScope(
      retry: noProviderRetry,
      overrides: [
        secureCredStoreProvider.overrideWithValue(store),
        onboardingStoreProvider.overrideWithValue(OnboardedStore()),
        appLockServiceProvider.overrideWithValue(lock),
        decoyIdentityProvider.overrideWithValue(FakeDecoyIdentity()),
        decoyBootProvider.overrideWithValue(boot),
        decoyPinIterationsProvider.overrideWithValue(_fast),
        notesStoreProvider.overrideWithValue(notes),
      ],
      child: const MoavDeployApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NotesApp), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.byType(ServersHomeScreen), findsNothing);
    expect(find.byType(ServersHomeScreen, skipOffstage: false), findsNothing);
    expect(find.byType(MoavMark, skipOffstage: false), findsNothing);
    expect(lock.gates, isEmpty, reason: 'no biometric prompt over the decoy');
    for (final t in tester.widgetList<Text>(find.byType(Text, skipOffstage: false))) {
      final s = t.data ?? t.textSpan?.toPlainText() ?? '';
      expect(s, isNot(contains('Demo')));
      expect(s, isNot(contains('example.org')));
      expect(s, isNot(contains('PRIVATE KEY')));
      expect(s, isNot(contains('MoaV')));
    }
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Notes');
    expect(app.theme!.textTheme.bodyMedium?.fontFamily ?? '', isNot(contains('Inter')));
    // The store is intact behind the decoy: nothing was wiped or moved.
    expect(store.profiles, [demoProfile]);
    expect(store.secrets['s1'], _pem);
  });

  test('the passcode never reaches the store or a log line', () async {
    final logged = <String>[];
    AppLog.sink = logged.add;
    addTearDown(() => AppLog.sink = null);
    final store = MemoryCredStore();
    final container = ProviderContainer(overrides: [
      secureCredStoreProvider.overrideWithValue(store),
      decoyIdentityProvider.overrideWithValue(FakeDecoyIdentity()),
      decoyPinIterationsProvider.overrideWithValue(_fast),
    ]);
    addTearDown(container.dispose);
    final n = container.read(decoyProvider.notifier);

    await n.enable(pin: _pin, gesture: DecoyGesture.tapTitleFiveTimes);
    final config = container.read(decoyProvider);
    expect(config.hasPin, isTrue);
    final persisted = store.decoy!.values.map((v) => '$v').join('\n');
    expect(persisted, isNot(contains(_pin)));
    expect(persisted, contains(config.pinHash));
    expect(config.toString(), isNot(contains(config.pinHash!)));
    expect(config.toString(), isNot(contains(config.salt!)));
    expect(config.toString(), isNot(contains(_pin)));

    expect(await n.verifyPin('0000'), PinCheck.wrong);
    expect(await n.verifyPin(_pin), PinCheck.ok);
    for (final line in logged) {
      expect(line, isNot(contains(_pin)));
      expect(line, isNot(contains('0000')));
      expect(line, isNot(contains(config.pinHash!)));
    }

    // Disabling forgets the hash as well as the flag.
    await n.disable();
    expect(store.decoy, isNull);
    expect(container.read(decoyProvider), DecoyConfig.off);
  });
}
