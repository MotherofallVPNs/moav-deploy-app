import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/moav_controller_factory.dart';
import '../../core/server_profile.dart';
import '../../security/secure_cred_store.dart';

final secureCredStoreProvider =
    Provider<SecureCredStore>((_) => SecureCredStore());

final moavControllerFactoryProvider = Provider<MoavControllerFactory>((ref) {
  final store = ref.watch(secureCredStoreProvider);
  return MoavControllerFactory(
    secretResolver: (profile) => store.readSecret(profile.id),
  );
});

/// One long-lived [MoavController] per saved server, so an SSH session opened
/// for a ping can be reused by the deploy screen. Keyed by profile id; the
/// profile itself is read (not watched) so list updates don't drop sessions.
final moavControllerProvider =
    Provider.family<MoavController, String>((ref, serverId) {
  final profiles = ref.read(serversProvider).value ?? const <ServerProfile>[];
  final profile = profiles.firstWhere(
    (p) => p.id == serverId,
    orElse: () => throw StateError('Unknown server $serverId'),
  );
  return ref.read(moavControllerFactoryProvider).forServer(profile);
});

/// The saved servers. Loaded from the secure store on first read.
class ServersNotifier extends AsyncNotifier<List<ServerProfile>> {
  SecureCredStore get _store => ref.read(secureCredStoreProvider);

  @override
  Future<List<ServerProfile>> build() => _store.loadProfiles();

  /// Persists a new server and its secret. The secret is written first so a
  /// listed profile never lacks its credential.
  Future<void> add(ServerProfile profile, {required String secret}) async {
    final current = state.value ?? const <ServerProfile>[];
    await _store.writeSecret(profile.id, secret);
    final next = [...current, profile];
    await _store.saveProfiles(next);
    state = AsyncData(next);
  }

  Future<void> remove(String id) async {
    final current = state.value ?? const <ServerProfile>[];
    final next = current.where((p) => p.id != id).toList(growable: false);
    await _store.saveProfiles(next);
    await _store.deleteSecret(id);
    await _store.deleteInstallHandle(id);
    ref.invalidate(moavControllerProvider(id));
    state = AsyncData(next);
  }
}

final serversProvider =
    AsyncNotifierProvider<ServersNotifier, List<ServerProfile>>(
  ServersNotifier.new,
);
