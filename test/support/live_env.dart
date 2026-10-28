import 'dart:io';

import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';

/// The `MOAV_TEST_*` variables the live suite reads (see docs/LIVE-CI.md).
///
/// `null` when any required variable is missing, which is how every live
/// test decides to skip. Nothing here opens a connection.
class LiveEnv {
  LiveEnv._({
    required this.host,
    required this.user,
    required this.keyPath,
    required this.port,
    this.domain,
  });

  /// Reads [env] (the process environment by default); `null` unless
  /// `MOAV_TEST_HOST`, `MOAV_TEST_USER` and `MOAV_TEST_SSH_KEY` are all set.
  static LiveEnv? fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    final host = e['MOAV_TEST_HOST'];
    final user = e['MOAV_TEST_USER'];
    var keyPath = e['MOAV_TEST_SSH_KEY'];
    if (host == null || user == null || keyPath == null) return null;
    if (host.isEmpty || user.isEmpty || keyPath.isEmpty) return null;
    if (keyPath.startsWith('~/')) {
      keyPath = '${e['HOME']}/${keyPath.substring(2)}';
    }
    return LiveEnv._(
      host: host,
      user: user,
      keyPath: keyPath,
      port: int.tryParse(e['MOAV_TEST_PORT'] ?? '') ?? 22,
      domain: e['MOAV_TEST_DOMAIN'],
    );
  }

  /// Skip reason every live test passes to `test(skip: ...)`.
  static const skipReason = 'MOAV_TEST_* env not set';

  final String host;
  final String user;

  /// Private key file, `~/` already expanded.
  final String keyPath;
  final int port;

  /// `MOAV_TEST_DOMAIN`, or `null` to fall back to [host].
  final String? domain;

  String get keyPem => File(keyPath).readAsStringSync();

  ServerProfile get profile => ServerProfile(
        id: 'live',
        label: host,
        host: host,
        port: port,
        username: user,
        authMethod: SshAuthMethod.importedKey,
      );

  /// A controller for the live box; dispose it in `tearDownAll`.
  SshMoavController controller() {
    final pem = keyPem;
    return SshMoavController(
      profile: profile,
      secretResolver: (_) async => pem,
    );
  }
}
