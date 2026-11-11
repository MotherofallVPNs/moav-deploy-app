import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/server_profile.dart';
import '../deploy/deploy_provider.dart';
import '../donate/donate_provider.dart';
import '../operate/operate_provider.dart';
import '../server/server_connection.dart';
import '../servers/servers_provider.dart';
import '../users/users_provider.dart';

/// Lifecycle of the built-in demo server.
///
/// The demo keeps its management state (users, service states, a running
/// job) inside one in-memory `DemoMoavController`. Entering and leaving the
/// demo both call [resetDemo], which drops that controller and every cached
/// value read through it, so the next visit starts from the baseline: stock
/// users, every service as on a healthy box. Whether MoaV is installed is
/// the one thing kept (in the secure store): a brand-new demo opens the
/// install flow once, and after it finishes every visit lands on the hub.

/// Saves the demo profile when it is not in the list yet and resets its
/// state. The caller then pushes the server hub for the returned profile.
Future<ServerProfile> prepareDemo(WidgetRef ref) async {
  final profile = await ref.read(serversProvider.notifier).addDemo();
  resetDemo(ref);
  return profile;
}

/// Back to the baseline: the demo controller and every provider that cached
/// something read through it are rebuilt. Real servers are not touched, and
/// neither is the remembered install result.
void resetDemo(WidgetRef ref) {
  const id = ServerProfile.demoId;
  // The controller first: the notifiers below read it again on rebuild.
  ref.invalidate(moavControllerProvider(id));
  ref.invalidate(serverConnectionProvider(id));
  ref.invalidate(deployProvider(id));
  ref.invalidate(statusProvider(id));
  ref.invalidate(doctorProvider(id));
  ref.invalidate(monitoringProvider(id));
  ref.invalidate(metricsProvider(id));
  ref.invalidate(chartsProvider(id));
  ref.invalidate(serverInfoProvider(id));
  ref.invalidate(serviceFlagsProvider(id));
  ref.invalidate(serviceActionsProvider(id));
  ref.invalidate(updateProvider(id));
  ref.invalidate(usersProvider(id));
  ref.invalidate(donateEnvProvider(id));
  ref.invalidate(donateOverviewProvider(id));
}

/// Wraps the demo's server hub: leaving it (back button or gesture) resets
/// the demo's management state, so re-entering shows the stock users again.
class DemoExitReset extends ConsumerWidget {
  const DemoExitReset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) resetDemo(ref);
        },
        child: child,
      );
}
