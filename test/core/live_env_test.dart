import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/server_profile.dart';

import '../support/live_env.dart';

/// The live suite's switch: every `test/live/*` file skips unless all three
/// required variables are present, so a CI runner without the secrets must
/// resolve to `null` here (see docs/LIVE-CI.md).
void main() {
  const full = {
    'MOAV_TEST_HOST': 'ci.example.org',
    'MOAV_TEST_USER': 'root',
    'MOAV_TEST_SSH_KEY': '/run/secrets/key',
  };

  test('absent or partial variables skip the live round', () {
    expect(LiveEnv.fromEnvironment(const {}), isNull);
    expect(LiveEnv.fromEnvironment(const {'MOAV_TEST_HOST': 'h'}), isNull);
    expect(
      LiveEnv.fromEnvironment(const {
        'MOAV_TEST_HOST': 'h',
        'MOAV_TEST_USER': 'root',
      }),
      isNull,
    );
    // GitHub passes an unset secret as an empty string, not as unset.
    expect(
      LiveEnv.fromEnvironment(const {
        'MOAV_TEST_HOST': '',
        'MOAV_TEST_USER': 'root',
        'MOAV_TEST_SSH_KEY': '/k',
      }),
      isNull,
    );
    expect(LiveEnv.skipReason, 'MOAV_TEST_* env not set');
  });

  test('the three required variables build a key-auth profile on port 22', () {
    final live = LiveEnv.fromEnvironment(full)!;
    expect(live.host, 'ci.example.org');
    expect(live.user, 'root');
    expect(live.keyPath, '/run/secrets/key');
    expect(live.port, 22);
    expect(live.domain, isNull);
    final p = live.profile;
    expect(p.id, 'live');
    expect(p.host, 'ci.example.org');
    expect(p.username, 'root');
    expect(p.authMethod, SshAuthMethod.importedKey);
  });

  test('port and domain are optional; a bad port falls back to 22', () {
    final live = LiveEnv.fromEnvironment({
      ...full,
      'MOAV_TEST_PORT': '2222',
      'MOAV_TEST_DOMAIN': 'vpn.example.org',
    })!;
    expect(live.port, 2222);
    expect(live.domain, 'vpn.example.org');
    expect(live.profile.port, 2222);
    expect(LiveEnv.fromEnvironment({...full, 'MOAV_TEST_PORT': 'ssh'})!.port, 22);
  });

  test('a ~/ key path expands against HOME', () {
    final live = LiveEnv.fromEnvironment({
      ...full,
      'MOAV_TEST_SSH_KEY': '~/.ssh/moav_ci',
      'HOME': '/home/runner',
    })!;
    expect(live.keyPath, '/home/runner/.ssh/moav_ci');
  });
}
