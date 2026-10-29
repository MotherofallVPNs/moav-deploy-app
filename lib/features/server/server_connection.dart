import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../servers/servers_provider.dart';

/// The connection check of one server (`ping`: reachability, authentication
/// and whether `moav` is installed), run when the server hub opens.
///
/// Shared so the deploy screen can ask for one fresh check after an install
/// finishes (`ref.invalidate`), which is what flips the hub's status row
/// from "not installed yet" to the installed version.
class ServerConnection extends AsyncNotifier<ConnectionCheck> {
  ServerConnection(this.serverId);

  final String serverId;

  @override
  Future<ConnectionCheck> build() =>
      ref.read(moavControllerProvider(serverId)).ping();
}

final serverConnectionProvider = AsyncNotifierProvider.autoDispose
    .family<ServerConnection, ConnectionCheck, String>(ServerConnection.new);
