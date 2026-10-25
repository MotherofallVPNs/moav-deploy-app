import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../security/key_service.dart';
import '../../security/secure_cred_store.dart';
import '../servers/servers_provider.dart';

class KeyringNotifier extends AsyncNotifier<List<StoredSshKey>> {
  SecureCredStore get _store => ref.read(secureCredStoreProvider);

  @override
  Future<List<StoredSshKey>> build() => _store.loadSshKeys();

  Future<StoredSshKey> add({
    required String label,
    required String privateKeyPem,
  }) async {
    final publicKey = const KeyService().publicKeyFromPem(privateKeyPem);
    if (publicKey == null) throw ArgumentError('Not a usable ed25519 key');
    final existing = (state.value ?? const <StoredSshKey>[])
        .where(
          (key) =>
              key.publicKey.split(' ').take(2).join(' ') ==
              publicKey.split(' ').take(2).join(' '),
        )
        .firstOrNull;
    if (existing != null) return existing;
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final key = StoredSshKey(
      id: id,
      label: label.trim().isEmpty ? 'Device key' : label.trim(),
      publicKey: publicKey,
      createdAt: DateTime.now().toUtc(),
    );
    await _store.writeSshKeySecret(id, privateKeyPem.trim());
    final next = [...(state.value ?? const <StoredSshKey>[]), key];
    await _store.saveSshKeys(next);
    state = AsyncData(next);
    return key;
  }

  Future<String?> secret(String id) => _store.readSshKeySecret(id);

  Future<void> rename(String id, String label) async {
    final next = [
      for (final key in state.value ?? const <StoredSshKey>[])
        if (key.id == id) key.copyWith(label: label.trim()) else key,
    ];
    await _store.saveSshKeys(next);
    state = AsyncData(next);
  }

  Future<void> remove(String id) async {
    final next = (state.value ?? const <StoredSshKey>[])
        .where((key) => key.id != id)
        .toList(growable: false);
    await _store.saveSshKeys(next);
    await _store.deleteSshKeySecret(id);
    state = AsyncData(next);
  }
}

final keyringProvider =
    AsyncNotifierProvider<KeyringNotifier, List<StoredSshKey>>(
      KeyringNotifier.new,
    );
