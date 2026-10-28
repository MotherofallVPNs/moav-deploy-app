import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/security/secure_cred_store.dart';

/// Minimal in-memory FlutterSecureStorage: only the five calls the store
/// uses, dispatched by name so option parameters need no mirroring.
class _FakeStorage implements FlutterSecureStorage {
  final data = <String, String>{};

  @override
  dynamic noSuchMethod(Invocation inv) {
    final key = inv.namedArguments[#key] as String?;
    switch (inv.memberName) {
      case #read:
        return Future<String?>.value(data[key]);
      case #write:
        data[key!] = inv.namedArguments[#value] as String;
        return Future<void>.value();
      case #delete:
        data.remove(key);
        return Future<void>.value();
      case #readAll:
        return Future<Map<String, String>>.value(Map.of(data));
      case #deleteAll:
        data.clear();
        return Future<void>.value();
    }
    return super.noSuchMethod(inv);
  }
}

/// Disguise mode (issue #15): the emergency wipe removes every secret but
/// keeps the disguise config, so a wipe under duress never turns the Notes
/// icon back into MoaV.
void main() {
  test('wipeAll keeps the disguise config and counts only what it removed',
      () async {
    final storage = _FakeStorage();
    final store = SecureCredStore(storage);
    await store.writeDecoy({'enabled': true, 'pinHash': 'h', 'salt': 's'});
    await store.writeSecret('s1', 'PRIVATE');
    await store.writeSshKeySecret('k1', 'PEM');
    await store.writeInstallHandle('s1', {'pid': 1});

    expect(await store.wipeAll(), 3);
    expect(storage.data.keys, [SecureCredStore.decoyKey]);
    expect((await store.readDecoy())?['enabled'], true);
    expect(await store.readSecret('s1'), isNull);
  });

  test('wipeAll without a disguise config empties the store', () async {
    final storage = _FakeStorage();
    final store = SecureCredStore(storage);
    await store.writeSecret('s1', 'PRIVATE');
    expect(await store.wipeAll(), 1);
    expect(storage.data, isEmpty);
    expect(await store.readDecoy(), isNull);
  });

  test('deleteDecoy removes the config', () async {
    final storage = _FakeStorage();
    final store = SecureCredStore(storage);
    await store.writeDecoy({'enabled': true});
    await store.deleteDecoy();
    expect(await store.readDecoy(), isNull);
  });
}
