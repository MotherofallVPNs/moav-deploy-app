import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/app.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/features/servers/add_server_form.dart';
import 'package:moav_deploy/features/servers/servers_provider.dart';
import 'package:moav_deploy/security/secure_cred_store.dart';

/// In-memory stand-in so tests never touch platform channels.
class _FakeCredStore implements SecureCredStore {
  List<ServerProfile> profiles = [];
  final Map<String, String> secrets = {};

  @override
  Future<List<ServerProfile>> loadProfiles() async => profiles;
  @override
  Future<void> saveProfiles(List<ServerProfile> p) async => profiles = p;
  @override
  Future<void> writeSecret(String id, String s) async => secrets[id] = s;
  @override
  Future<String?> readSecret(String id) async => secrets[id];
  @override
  Future<void> deleteSecret(String id) async => secrets.remove(id);
  @override
  Future<void> wipeAll() async {
    profiles = [];
    secrets.clear();
  }
}

Widget _app(_FakeCredStore store) => ProviderScope(
      overrides: [secureCredStoreProvider.overrideWithValue(store)],
      child: const MoavDeployApp(lockEnabled: false),
    );

void main() {
  testWidgets('home shows empty state and opens add-server form',
      (tester) async {
    await tester.pumpWidget(_app(_FakeCredStore()));
    await tester.pumpAndSettle();

    expect(find.text('No servers yet'), findsOneWidget);

    await tester.tap(find.text('Add server'));
    await tester.pumpAndSettle();

    expect(find.text('Host'), findsOneWidget);
    expect(find.text('Generate key'), findsOneWidget);
  });

  testWidgets('saving a password-auth server lists it and stores the secret',
      (tester) async {
    final store = _FakeCredStore();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add server'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Host'), 'vpn.example.org');
    await tester.tap(find.text('Password'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'hunter2');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save server'));
    await tester.pumpAndSettle();

    expect(find.text('vpn.example.org'), findsOneWidget);
    expect(store.profiles.single.authMethod, SshAuthMethod.password);
    expect(store.secrets.values.single, 'hunter2');
  });

  test('form validation', () {
    const empty = AddServerFormState();
    expect(empty.isValid, isFalse);
    expect(empty.hostError, isNotNull);

    const ok = AddServerFormState(
      host: 'h',
      authChoice: AuthChoice.password,
      password: 'p',
    );
    expect(ok.isValid, isTrue);
    expect(ok.toProfile('x').label, 'h');

    const badPort = AddServerFormState(host: 'h', port: '70000');
    expect(badPort.portError, isNotNull);
  });
}
