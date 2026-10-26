import 'moav_controller.dart';
import 'server_profile.dart';
import 'ssh_moav_controller.dart';

/// Builds the right [MoavController] for a server.
///
/// Always [SshMoavController] today. An API-backed controller can be selected
/// here later when a profile advertises a control API endpoint. The UI never
/// depends on the concrete type.
class MoavControllerFactory {
  const MoavControllerFactory({required this.secretResolver});

  final SecretResolver secretResolver;

  MoavController forServer(ServerProfile profile) {
    return SshMoavController(
      profile: profile,
      secretResolver: secretResolver,
    );
  }
}
