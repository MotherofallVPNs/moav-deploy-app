import 'moav_controller.dart';
import 'server_profile.dart';
import 'ssh_moav_controller.dart';

/// Builds the right [MoavController] for a server.
///
/// Phase 1: always [SshMoavController]. Phase 2 adds `ApiMoavController` and
/// selects it when the profile advertises a control API endpoint. The UI
/// never depends on the concrete type.
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
