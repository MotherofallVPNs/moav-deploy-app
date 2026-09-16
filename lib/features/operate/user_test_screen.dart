import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/error_view.dart';
import 'operate_provider.dart';

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
    return MoavScaffold(
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
        loading: () => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Connecting through every protocol from the server itself. '
                  'The first run builds a client image and can take several minutes.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            MoavCard(
              accent: true,
              child: Row(
                children: [
                  StatusPill.result(
                    m.overall ?? (m.allPass ? CheckResult.pass : CheckResult.fail),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.allPass ? 'All tested protocols pass' : 'Some protocols need attention',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${m.count(CheckResult.pass)} pass · ${m.count(CheckResult.warn)} warn · '
                          '${m.count(CheckResult.fail)} fail · ${m.count(CheckResult.skip)} skipped',
                          style: moavMono(size: 11, weight: FontWeight.w400, color: MoavColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SectionHeader('Protocol matrix'),
            MoavCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, r) in m.results.indexed) ...[
                    if (i > 0) const Divider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.protocol, style: moavMono(size: 13, weight: FontWeight.w600)),
                                if (r.detail != null) ...[
                                  const SizedBox(height: 2),
                                  Text(r.detail!, style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          StatusPill.result(r.result),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
