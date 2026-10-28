import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/security/secure_cred_store.dart';

/// In-memory [SecureCredStore] so tests never touch platform channels.
///
/// Shared by the widget tests and the screenshot gallery; seed the public
/// fields directly (`..profiles = [...]`, `..secrets['id'] = 'pem'`).
class MemoryCredStore implements SecureCredStore {
  List<ServerProfile> profiles = [];
  List<StoredSshKey> sshKeys = [];
  final Map<String, String> secrets = {};
  final Map<String, String> sshKeySecrets = {};
  final Map<String, Map<String, Object?>> installHandles = {};
  Map<String, Object?>? decoy;

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
  Future<List<StoredSshKey>> loadSshKeys() async => sshKeys;
  @override
  Future<void> saveSshKeys(List<StoredSshKey> keys) async => sshKeys = keys;
  @override
  Future<void> writeSshKeySecret(String id, String pem) async =>
      sshKeySecrets[id] = pem;
  @override
  Future<String?> readSshKeySecret(String id) async => sshKeySecrets[id];
  @override
  Future<void> deleteSshKeySecret(String id) async => sshKeySecrets.remove(id);
  @override
  Future<void> writeInstallHandle(String id, Map<String, Object?> json) async =>
      installHandles[id] = json;
  @override
  Future<Map<String, Object?>?> readInstallHandle(String id) async =>
      installHandles[id];
  @override
  Future<void> deleteInstallHandle(String id) async =>
      installHandles.remove(id);
  @override
  Future<Map<String, Object?>?> readDecoy() async => decoy;
  @override
  Future<void> writeDecoy(Map<String, Object?> json) async => decoy = json;
  @override
  Future<void> deleteDecoy() async => decoy = null;
  @override
  Future<List<String>> listKeys() async => [
        ...secrets.keys,
        ...installHandles.keys,
        ...sshKeySecrets.keys,
      ];
  @override
  Future<int> wipeAll() async {
    final removed = profiles.length + secrets.length + installHandles.length;
    profiles = [];
    secrets.clear();
    installHandles.clear();
    sshKeys = [];
    sshKeySecrets.clear();
    return removed;
  }
}
