import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/server_profile.dart';

/// Thin wrapper over [FlutterSecureStorage] so the rest of the app never
/// touches storage keys directly.
///
/// Backed by iOS Keychain (`first_unlock_this_device`, no iCloud sync) and
/// Android Keystore-wrapped AES-GCM storage. Server profiles (non-secret) and
/// per-server secrets are stored under separate keys so a profile list can be
/// shown without pulling secrets into memory.
class SecureCredStore {
  SecureCredStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
              synchronizable: false,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _profilesKey = 'moav.servers.v1';
  static const _sshKeysKey = 'moav.sshkeys.v1';
  static String _secretKey(String serverId) => 'moav.secret.v1.$serverId';
  static String _sshKeySecret(String keyId) => 'moav.sshkey.v1.$keyId';
  static String _installKey(String serverId) => 'moav.install.v1.$serverId';

  /// Disguise settings (`DecoyConfig` JSON). The only key [wipeAll] keeps:
  /// a wipe under duress must not turn the Notes icon back into MoaV.
  static const decoyKey = 'moav.decoy.v1';

  Future<List<ServerProfile>> loadProfiles() async {
    final raw = await _storage.read(key: _profilesKey);
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => ServerProfile.fromJson(e as Map<String, Object?>))
        .toList(growable: false);
  }

  Future<void> saveProfiles(List<ServerProfile> profiles) {
    final encoded = jsonEncode(profiles.map((p) => p.toJson()).toList());
    return _storage.write(key: _profilesKey, value: encoded);
  }

  /// Stores the private key PEM or password for a server.
  Future<void> writeSecret(String serverId, String secret) =>
      _storage.write(key: _secretKey(serverId), value: secret);

  Future<String?> readSecret(String serverId) =>
      _storage.read(key: _secretKey(serverId));

  Future<void> deleteSecret(String serverId) =>
      _storage.delete(key: _secretKey(serverId));

  Future<List<StoredSshKey>> loadSshKeys() async {
    final raw = await _storage.read(key: _sshKeysKey);
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => StoredSshKey.fromJson(e as Map<String, Object?>))
        .toList(growable: false);
  }

  Future<void> saveSshKeys(List<StoredSshKey> keys) => _storage.write(
    key: _sshKeysKey,
    value: jsonEncode(keys.map((k) => k.toJson()).toList()),
  );

  Future<void> writeSshKeySecret(String keyId, String privateKeyPem) =>
      _storage.write(key: _sshKeySecret(keyId), value: privateKeyPem);

  Future<String?> readSshKeySecret(String keyId) =>
      _storage.read(key: _sshKeySecret(keyId));

  Future<void> deleteSshKeySecret(String keyId) =>
      _storage.delete(key: _sshKeySecret(keyId));

  /// Remembers a detached install job so it can be re-attached after the app
  /// was suspended or restarted. Stored as JSON (see `InstallHandle.toJson`).
  Future<void> writeInstallHandle(String serverId, Map<String, Object?> json) =>
      _storage.write(key: _installKey(serverId), value: jsonEncode(json));

  Future<Map<String, Object?>?> readInstallHandle(String serverId) async {
    final raw = await _storage.read(key: _installKey(serverId));
    if (raw == null || raw.isEmpty) return null;
    return jsonDecode(raw) as Map<String, Object?>;
  }

  Future<void> deleteInstallHandle(String serverId) =>
      _storage.delete(key: _installKey(serverId));

  Future<Map<String, Object?>?> readDecoy() async {
    final raw = await _storage.read(key: decoyKey);
    if (raw == null || raw.isEmpty) return null;
    return jsonDecode(raw) as Map<String, Object?>;
  }

  Future<void> writeDecoy(Map<String, Object?> json) =>
      _storage.write(key: decoyKey, value: jsonEncode(json));

  Future<void> deleteDecoy() => _storage.delete(key: decoyKey);

  /// Every key currently held, for the wipe report and for tests.
  Future<List<String>> listKeys() async =>
      (await _storage.readAll()).keys.toList();

  /// Device-seizure quick wipe: removes every server, secret and install
  /// handle from the platform secure store. The disguise config
  /// ([decoyKey]) is the one entry written back afterwards, so the app
  /// keeps its Notes identity (and the passcode that reveals it) after a
  /// wipe; the disguise screen can turn it off deliberately.
  ///
  /// Deletes each key individually **and** calls `deleteAll`, then reads the
  /// store back and refuses to report success while anything else is left.
  /// Returns the number of entries removed.
  Future<int> wipeAll() async {
    final before = await _storage.readAll();
    final decoy = before[decoyKey];
    for (final key in before.keys) {
      await _storage.delete(key: key);
    }
    await _storage.deleteAll();
    if (decoy != null) {
      await _storage.write(key: decoyKey, value: decoy);
    }
    final after = await _storage.readAll()
      ..remove(decoyKey);
    if (after.isNotEmpty) {
      throw StateError(
        'Secure storage still holds ${after.length} item(s) after wipe',
      );
    }
    return before.length - (decoy == null ? 0 : 1);
  }
}

class StoredSshKey {
  const StoredSshKey({
    required this.id,
    required this.label,
    required this.publicKey,
    required this.createdAt,
  });

  final String id;
  final String label;
  final String publicKey;
  final DateTime createdAt;

  StoredSshKey copyWith({String? label}) => StoredSshKey(
    id: id,
    label: label ?? this.label,
    publicKey: publicKey,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'publicKey': publicKey,
    'createdAt': createdAt.toIso8601String(),
  };

  factory StoredSshKey.fromJson(Map<String, Object?> json) => StoredSshKey(
    id: json['id'] as String,
    label: json['label'] as String,
    publicKey: json['publicKey'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
