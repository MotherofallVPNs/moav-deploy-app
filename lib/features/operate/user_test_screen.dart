import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import '../../widgets/error_view.dart';
import 'operate_provider.dart';
import 'operate_screen.dart';

/// Runs `moav test <user> --json` and shows the per-protocol result matrix.
class UserTestScreen extends ConsumerWidget {
  const UserTestScreen({super.key, required this.profile, required this.user});

  final ServerProfile profile;
  final String user;

  static Route<void> route(ServerProfile profile, String user) =>
      MaterialPageRoute(builder: (_) => UserTestScreen(profile: profile, user: user));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (serverId: profile.id, user: user);
    final matrix = ref.watch(userTestProvider(key));
    return Scaffold(
      appBar: AppBar(
        title: Text('Test · $user'),
        actions: [
          IconButton(
            icon: const Icon(Icons.replay),
            tooltip: 'Run again',
            onPressed: () => ref.invalidate(userTestProvider(key)),
          ),
        ],
      ),
      body: matrix.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Connecting through every protocol from the server itself. '
                  'The first run builds a client image and can take several minutes.',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(userTestProvider(key)),
          retryLabel: 'Run again',
        ),
        data: (m) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ResultIcon(m.overall ?? (m.allPass ? CheckResult.pass : CheckResult.fail)),
              title: Text(m.allPass ? 'All tested protocols pass' : 'Some protocols need attention'),
              subtitle: Text(
                '${m.count(CheckResult.pass)} pass · ${m.count(CheckResult.warn)} warn · '
                '${m.count(CheckResult.fail)} fail · ${m.count(CheckResult.skip)} skipped',
              ),
            ),
            const Divider(),
            for (final r in m.results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ResultIcon(r.result),
                title: Text(r.protocol),
                subtitle: r.detail == null ? null : Text(r.detail!),
                isThreeLine: (r.detail?.length ?? 0) > 60,
              ),
          ],
        ),
      ),
    );
  }
}
