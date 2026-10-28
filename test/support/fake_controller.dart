import 'package:moav_deploy/core/donate.dart';
import 'package:moav_deploy/core/donate_cli.dart';
import 'package:moav_deploy/core/moav_controller.dart';
import 'package:moav_deploy/core/moav_controller_factory.dart';
import 'package:moav_deploy/core/server_profile.dart';

/// Base for widget-test controllers: extend it and override only what the
/// screen under test calls. Anything else throws, so an unexpected server
/// round trip fails the test instead of silently answering.
class StubMoavController implements MoavController {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  // Declared so subclasses can keep the interface's non-nullable defaults
  // (a noSuchMethod forwarder would type the optionals as nullable).
  @override
  Future<DonateResult> donateConfigs({
    required int count,
    String prefix = DonateCli.defaultPrefix,
    bool force = false,
    OutputSink? onOutput,
  }) =>
      throw UnimplementedError('donateConfigs');
}

/// Hands every server the same controller.
class FakeControllerFactory extends MoavControllerFactory {
  FakeControllerFactory(this.controller)
      : super(secretResolver: (_) async => null);

  final MoavController controller;

  @override
  MoavController forServer(ServerProfile profile) => controller;
}

/// A tunnel that records its remote port and whether it was closed.
class FakeTunnel implements ServerTunnel {
  FakeTunnel(this.remotePort, {this.localPort = 45000});

  final int remotePort;
  var closed = false;

  @override
  final int localPort;

  @override
  Uri uri({String scheme = 'https', String path = '/'}) =>
      Uri(scheme: scheme, host: '127.0.0.1', port: localPort, path: path);

  @override
  bool get isOpen => !closed;

  @override
  Future<void> close() async => closed = true;
}

/// The saved server most widget tests open: an imported-key profile.
const demoProfile = ServerProfile(
  id: 's1',
  label: 'Demo',
  host: 'demo.example.org',
  port: 22,
  username: 'root',
  authMethod: SshAuthMethod.importedKey,
);

/// [demoProfile] with a key the app generated (changes the card label).
const demoKeyProfile = ServerProfile(
  id: 's1',
  label: 'Demo',
  host: 'demo.example.org',
  port: 22,
  username: 'root',
  authMethod: SshAuthMethod.generatedKey,
);
