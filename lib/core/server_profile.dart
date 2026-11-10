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
    this.isDemo = false,
  });

  final String id;
  final String label;
  final String host;
  final int port;
  final String username;
  final SshAuthMethod authMethod;

  /// The built-in demo server: every operation is emulated in memory by
  /// `DemoMoavController`. No SSH, no secret, no network.
  final bool isDemo;

  /// Id of the one demo profile; `ServerProfile.demo` is the only profile
  /// that carries it.
  static const demoId = 'demo';

  /// The demo server as saved in the profile list. Documentation values
  /// only (RFC 2606 domain, TEST-NET-3 address), never dialled.
  static const demo = ServerProfile(
    id: demoId,
    label: 'Demo server',
    host: 'demo.example.org',
    port: 22,
    username: 'moav',
    authMethod: SshAuthMethod.importedKey,
    isDemo: true,
  );

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
        isDemo: isDemo,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'username': username,
        'authMethod': authMethod.name,
        if (isDemo) 'isDemo': true,
      };

  factory ServerProfile.fromJson(Map<String, Object?> json) => ServerProfile(
        id: json['id'] as String,
        label: json['label'] as String,
        host: json['host'] as String,
        port: json['port'] as int,
        username: json['username'] as String,
        authMethod: SshAuthMethod.values.byName(json['authMethod'] as String),
        isDemo: json['isDemo'] == true,
      );

  @override
  String toString() =>
      'ServerProfile($username@$host:$port, $authMethod${isDemo ? ', demo' : ''})';
}
