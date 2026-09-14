import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/ssh_moav_controller.dart';
import '../servers/servers_provider.dart';
import '../users/users_provider.dart';

final statusProvider =
    FutureProvider.autoDispose.family<ServiceStatusReport, String>(
  (ref, serverId) => ref.read(moavControllerProvider(serverId)).status(),
);

final doctorProvider = FutureProvider.autoDispose.family<DoctorReport, String>(
  (ref, serverId) => ref.read(moavControllerProvider(serverId)).doctor(),
);

final monitoringProvider =
    FutureProvider.autoDispose.family<Monitoring, String>(
  (ref, serverId) => ref.read(moavControllerProvider(serverId)).monitoring(),
);

/// Runs `moav test <user>` when first watched (minutes on a cold image).
final userTestProvider =
    FutureProvider.autoDispose.family<TestMatrix, BundleKey>(
  (ref, key) => ref.read(moavControllerProvider(key.serverId)).testUser(key.user),
);

class ServiceActionState {
  const ServiceActionState({this.running, this.message, this.error});

  /// The action in flight, if any.
  final ServiceAction? running;
  final String? message;
  final String? error;

  bool get busy => running != null;
}

/// Serialises service actions for one server and refreshes status after.
class ServiceActionsNotifier extends Notifier<ServiceActionState> {
  ServiceActionsNotifier(this.serverId);

  final String serverId;

  @override
  ServiceActionState build() => const ServiceActionState();

  Future<void> run(ServiceAction action) async {
    if (state.busy) return;
    state = ServiceActionState(running: action);
    try {
      await ref.read(moavControllerProvider(serverId)).service(action);
      if (!ref.mounted) return;
      state = ServiceActionState(message: '${describe(action)} done');
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = ServiceActionState(error: SshMoavController.describeError(e));
    } finally {
      ref.invalidate(statusProvider(serverId));
      if (action.kind == ServiceActionKind.regenerateUsers) {
        ref.invalidate(usersProvider(serverId));
      }
    }
  }

  static String describe(ServiceAction a) {
    final verb = switch (a.kind) {
      ServiceActionKind.start => 'Start',
      ServiceActionKind.stop => 'Stop',
      ServiceActionKind.restart => 'Restart',
      ServiceActionKind.regenerateUsers => 'Regenerate users',
    };
    if (a.kind == ServiceActionKind.regenerateUsers) return verb;
    return '$verb ${a.service ?? 'all services'}';
  }
}

final serviceActionsProvider = NotifierProvider.autoDispose
    .family<ServiceActionsNotifier, ServiceActionState, String>(
  ServiceActionsNotifier.new,
);
