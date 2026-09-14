import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_error.dart';
import '../../core/ssh_moav_controller.dart';
import '../../security/wipe_service.dart';
import '../deploy/deploy_provider.dart';
import '../operate/operate_provider.dart';
import '../servers/servers_provider.dart';
import '../users/users_provider.dart';

final wipeServiceProvider = Provider<WipeService>(
  (ref) => WipeService(store: ref.watch(secureCredStoreProvider)),
);

class WipeState {
  const WipeState({this.busy = false, this.report, this.error});

  final bool busy;
  final WipeReport? report;
  final AppError? error;
}

/// Runs the quick wipe and tears down everything the app holds in memory:
/// open SSH sessions, cached user lists, bundles, status and test results.
class WipeNotifier extends Notifier<WipeState> {
  @override
  WipeState build() => const WipeState();

  Future<WipeReport?> wipe() async {
    if (state.busy) return null;
    state = const WipeState(busy: true);

    // Close SSH sessions first so nothing is in flight while keys vanish.
    final profiles = ref.read(serversProvider).value ?? const [];
    for (final p in profiles) {
      try {
        final c = ref.read(moavControllerProvider(p.id));
        if (c is SshMoavController) c.dispose();
      } on Object {
        // Provider may not have been created; nothing to close.
      }
    }

    try {
      final report = await ref.read(wipeServiceProvider).wipe();
      _dropInMemoryState();
      state = WipeState(report: report);
      return report;
    } on Object catch (e) {
      _dropInMemoryState();
      state = WipeState(error: AppError.from(e));
      return null;
    }
  }

  void _dropInMemoryState() {
    ref.invalidate(bundleProvider);
    ref.invalidate(usersProvider);
    ref.invalidate(userTestProvider);
    ref.invalidate(statusProvider);
    ref.invalidate(doctorProvider);
    ref.invalidate(monitoringProvider);
    ref.invalidate(deployProvider);
    ref.invalidate(moavControllerProvider);
    ref.invalidate(serversProvider);
  }
}

final wipeProvider = NotifierProvider<WipeNotifier, WipeState>(WipeNotifier.new);
