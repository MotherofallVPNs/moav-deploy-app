import 'package:moav_deploy/core/moav_cli.dart';
import 'package:moav_deploy/core/server_profile.dart';
import 'package:moav_deploy/core/ssh_connection.dart';
import 'package:moav_deploy/core/ssh_moav_controller.dart';

/// How [FakeBox] looks a command up in its scripted responses.
enum BoxMatch {
  /// The whole command string.
  exact,

  /// The part after `MoavCli.prelude` and `"$M" `, e.g. `status --json`.
  tail,

  /// The first response whose key is a substring of the command.
  contains,
}

/// Scripts the remote box for [SshMoavController] without SSH: answers each
/// command from [responses], records every command and file upload, and
/// raises [SshCommandException] on a non-zero exit unless the caller allowed
/// failure, exactly like `SshConnection.run`.
class FakeBox {
  FakeBox(
    this.responses, {
    this.match = BoxMatch.exact,
    this.fallback,
  });

  /// Keys are command tails (`status --json`); [ran] records tails too.
  FakeBox.byTail(Map<String, SshOutput> responses)
      : this(responses, match: BoxMatch.tail);

  /// Keys are substrings; unmatched commands succeed with empty output.
  FakeBox.containing(
    Map<String, SshOutput> responses, {
    SshOutput fallback = const SshOutput(stdout: '', stderr: '', exitCode: 0),
  }) : this(responses, match: BoxMatch.contains, fallback: fallback);

  /// Every command succeeds with the same [stdout].
  FakeBox.always(String stdout)
      : this(const {}, match: BoxMatch.contains, fallback: ok(stdout));

  final Map<String, SshOutput> responses;
  final BoxMatch match;

  /// Answer for commands no entry matches; `null` makes them a test error.
  final SshOutput? fallback;

  /// Commands in order, as the lookup key (the tail in [BoxMatch.tail]).
  final ran = <String>[];

  /// Full command strings in order, whatever the match mode.
  final commands = <String>[];

  final uploads = <(String path, String content, String mode)>[];

  Future<SshOutput> run(
    String command, {
    bool allowFailure = false,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final key = match == BoxMatch.tail ? tail(command) : command;
    ran.add(key);
    commands.add(command);
    SshOutput? out;
    if (match == BoxMatch.contains) {
      for (final e in responses.entries) {
        if (command.contains(e.key)) {
          out = e.value;
          break;
        }
      }
    } else {
      out = responses[key];
    }
    out ??= fallback;
    if (out == null) throw StateError('unscripted command: $key');
    if (!allowFailure && out.exitCode != 0) {
      throw SshCommandException(command, out);
    }
    return out;
  }

  Future<void> write(String path, String content, {String mode = '600'}) async {
    uploads.add((path, content, mode));
  }

  /// A controller wired to this box; see [controllerFor].
  SshMoavController get controller => controllerFor(this);
}

SshOutput ok(String stdout, {String stderr = ''}) =>
    SshOutput(stdout: stdout, stderr: stderr, exitCode: 0);

SshOutput failed(String stdout, {String stderr = '', int code = 1}) =>
    SshOutput(stdout: stdout, stderr: stderr, exitCode: code);

/// The command without `MoavCli.prelude` and the `"$M" ` that follows it.
String tail(String command) =>
    command.substring(MoavCli.prelude.length + '"\$M" '.length);

/// A profile for unit tests; the secret resolver below never runs.
const unitProfile = ServerProfile(
  id: 't',
  label: 't',
  host: 'h',
  port: 22,
  username: 'root',
  authMethod: SshAuthMethod.importedKey,
);

/// An [SshMoavController] whose every command and upload goes to [box].
SshMoavController controllerFor(FakeBox box) => SshMoavController(
      profile: unitProfile,
      secretResolver: (_) async => throw StateError('no ssh in unit tests'),
      runner: box.run,
      fileWriter: box.write,
    );
