import 'demo_moav_controller.dart';
import 'moav_controller.dart';
import 'server_profile.dart';
import 'ssh_moav_controller.dart';

/// Builds the right [MoavController] for a server.
///
/// [SshMoavController] for every real server; [DemoMoavController] for the
/// built-in demo profile, which never resolves a secret, opens SSH or
/// touches the network. An API-backed controller can be selected here later
/// when a profile advertises a control API endpoint. The UI never depends
/// on the concrete type.
class MoavControllerFactory {
  const MoavControllerFactory({
    required this.secretResolver,
    this.demoInstalls,
  });

  final SecretResolver secretResolver;

  /// Where the demo remembers a finished install; null keeps it in memory.
  final DemoInstallStore? demoInstalls;

  MoavController forServer(ServerProfile profile) {
    if (profile.isDemo) return DemoMoavController(installStore: demoInstalls);
    return SshMoavController(
      profile: profile,
      secretResolver: secretResolver,
    );
  }
}
