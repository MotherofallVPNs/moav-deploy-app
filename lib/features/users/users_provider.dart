import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../servers/servers_provider.dart';

/// The users on one server. Loaded on first watch; [add] / [remove] update
/// the list optimistically after the CLI confirms.
class UsersNotifier extends AsyncNotifier<List<MoavUser>> {
  UsersNotifier(this.serverId);

  final String serverId;

  MoavController get _controller => ref.read(moavControllerProvider(serverId));

  @override
  Future<List<MoavUser>> build() => _controller.listUsers();

  Future<void> refresh() async {
    state = await AsyncValue.guard(_controller.listUsers);
  }

  Future<MoavUser> add(String name) async {
    final user = await _controller.addUser(name);
    final current = state.value ?? const <MoavUser>[];
    state = AsyncData(
      [...current.where((u) => u.name != user.name), user]
        ..sort((a, b) => a.name.compareTo(b.name)),
    );
    return user;
  }

  Future<void> remove(String name) async {
    await _controller.removeUser(name);
    final current = state.value ?? const <MoavUser>[];
    state = AsyncData(current.where((u) => u.name != name).toList());
  }
}

final usersProvider = AsyncNotifierProvider.autoDispose
    .family<UsersNotifier, List<MoavUser>, String>(UsersNotifier.new);

typedef BundleKey = ({String serverId, String user});

/// A user's bundle, fetched over SFTP on demand.
final bundleProvider =
    FutureProvider.autoDispose.family<Bundle, BundleKey>((ref, key) {
  return ref.read(moavControllerProvider(key.serverId)).getBundle(key.user);
});
