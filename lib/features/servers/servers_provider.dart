import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    state = AsyncData(next);
  }
}

final serversProvider =
    AsyncNotifierProvider<ServersNotifier, List<ServerProfile>>(
  ServersNotifier.new,
);
