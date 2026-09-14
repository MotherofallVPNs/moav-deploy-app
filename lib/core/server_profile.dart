/// How the app authenticates to a server over SSH.
enum SshAuthMethod {
  /// ed25519 key generated on-device; private key lives in the secure store.
  generatedKey,

  /// ed25519 key pasted/imported by the user; stored in the secure store.
  importedKey,

  /// Password auth. Fallback only (see docs/ARCHITECTURE.md → Security).
  password,
}

/// Non-secret description of a saved server.
///
/// Secrets (private key, password) are never on this object; they are looked
/// up from [SecureCredStore] by [id].
class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
    required this.username,
    required this.authMethod,
  });

  final String id;
  final String label;
  final String host;
  final int port;
  final String username;
  final SshAuthMethod authMethod;

  ServerProfile copyWith({
    String? label,
    String? host,
    int? port,
    String? username,
    SshAuthMethod? authMethod,
  }) =>
      ServerProfile(
        id: id,
        label: label ?? this.label,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        authMethod: authMethod ?? this.authMethod,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'username': username,
        'authMethod': authMethod.name,
      };

  factory ServerProfile.fromJson(Map<String, Object?> json) => ServerProfile(
        id: json['id'] as String,
        label: json['label'] as String,
        host: json['host'] as String,
        port: json['port'] as int,
        username: json['username'] as String,
        authMethod: SshAuthMethod.values.byName(json['authMethod'] as String),
      );

  @override
  String toString() => 'ServerProfile($username@$host:$port, $authMethod)';
}
