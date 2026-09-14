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
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
                synchronizable: false,
              ),
            );

  final FlutterSecureStorage _storage;

  static const _profilesKey = 'moav.servers.v1';
  static String _secretKey(String serverId) => 'moav.secret.v1.$serverId';
  static String _installKey(String serverId) => 'moav.install.v1.$serverId';

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

  /// Device-seizure quick wipe: removes every server and secret.
  Future<void> wipeAll() => _storage.deleteAll();
}
