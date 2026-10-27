import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/moav_services.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/moav_app_bar.dart';
import '../../widgets/error_view.dart';
import '../../widgets/log_view.dart';
import 'deploy_provider.dart';

/// Deploy MoaV on a server: collects installer inputs, launches the detached
/// install, and streams the server-side log with live status.
class DeployScreen extends ConsumerWidget {
  const DeployScreen({super.key, required this.profile});

  final ServerProfile profile;

  static Route<void> route(ServerProfile profile) =>
      MaterialPageRoute(builder: (_) => DeployScreen(profile: profile));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(deployProvider(profile.id));
    final notifier = ref.read(deployProvider(profile.id).notifier);

    return MoavScaffold(
      appBar: MoavAppBar(
        title: Text('Deploy · ${profile.label}'),
        actions: [
          if (state.handle != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: notifier.refresh,
            ),
        ],
      ),
      body: state.handle == null
          ? _InstallForm(state: state, onStart: notifier.start)
          : _JobView(state: state, onReset: notifier.reset),
    );
  }
}

class _InstallForm extends StatefulWidget {
  const _InstallForm({required this.state, required this.onStart});

  final DeployState state;
  final Future<void> Function(InstallSpec) onStart;

  @override
  State<_InstallForm> createState() => _InstallFormState();
}

class _InstallFormState extends State<_InstallForm> {
  final _domain = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _branch = TextEditingController();

  /// Profiles to build and start; starts as upstream's own default set.
  final _profiles = <String>{...MoavProfiles.defaults};

  @override
  void dispose() {
    _domain.dispose();
    _email.dispose();
    _password.dispose();
    _branch.dispose();
    super.dispose();
  }

  String? get _passwordError {
    final p = _password.text;
    if (p.contains(RegExp(r'["\\$`]'))) {
      return 'Avoid " \\ \$ ` in the admin password';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        MoavCard(
          accent: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconBadge(Icons.rocket_launch_outlined, gradient: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Idempotent install', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Runs the MoaV installer on the server in the background. '
                      'Safe to re-run: an existing install is kept, users and '
                      'keys are never touched, and settings below only fill '
                      'values that are not configured yet.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('Installer inputs'),
        TextField(
          controller: _domain,
          decoration: const InputDecoration(
            labelText: 'Domain',
            hintText: 'vpn.example.org (blank = keep existing / domainless)',
          ),
          style: moavMono(size: 14),
          keyboardType: TextInputType.url,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          decoration: const InputDecoration(
            labelText: "Let's Encrypt email",
            hintText: 'needed when a domain is set',
          ),
          style: moavMono(size: 14),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          decoration: InputDecoration(
            labelText: 'Admin dashboard password',
            errorText: _passwordError,
          ),
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _branch,
          decoration: const InputDecoration(
            labelText: 'MoaV branch (optional)',
            hintText: 'main',
          ),
          style: moavMono(size: 14),
          autocorrect: false,
          onChanged: (_) => setState(() {}),
        ),
        SectionHeader(
          'Services',
          trailing: TextButton(
            onPressed: _profiles.length == MoavProfiles.defaults.length &&
                    _profiles.containsAll(MoavProfiles.defaults)
                ? null
                : () => setState(() => _profiles
                  ..clear()
                  ..addAll(MoavProfiles.defaults)),
            child: const Text('Reset to default'),
          ),
        ),
        Text(
          'Written to DEFAULT_PROFILES before moav bootstrap --yes; the '
          'matching ENABLE_* flags are set only in a .env this install '
          'creates. Change them later from the Services tab.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        ServiceSelection(
          selected: _profiles,
          onChanged: (name, on) => setState(() {
            if (on) {
              _profiles.add(name);
            } else {
              _profiles.remove(name);
            }
          }),
        ),
        if (_profiles.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Select at least one service.',
            style: theme.textTheme.bodySmall?.copyWith(color: MoavColors.fail),
          ),
        ],
        if (s.error != null) ...[
          const SizedBox(height: 16),
          ErrorBanner(error: s.error!),
        ],
        const SizedBox(height: 24),
        GradientButton(
          onPressed: s.starting || _passwordError != null || _profiles.isEmpty
              ? null
              : _start,
          busy: s.starting,
          expand: true,
          icon: Icons.rocket_launch_outlined,
          label: 'Start install',
        ),
      ],
    );
  }

  void _start() {
    final branch = _branch.text.trim();
    widget.onStart(
      InstallSpec(
        domain: _domain.text.trim(),
        email: _email.text.trim(),
        adminPassword: _password.text,
        extraEnv: branch.isEmpty ? const {} : {'MOAV_BRANCH': branch},
        // Catalog order, so DEFAULT_PROFILES reads like upstream writes it.
        profiles: [
          for (final p in MoavProfiles.all)
            if (_profiles.contains(p.name)) p.name,
        ],
      ),
    );
  }
}

/// One checkbox per MoaV profile, in upstream's menu order.
class ServiceSelection extends StatelessWidget {
  const ServiceSelection({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<String> selected;
  final void Function(String profile, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MoavCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, p) in MoavProfiles.all.indexed) ...[
            if (i > 0) const Divider(),
            CheckboxListTile(
              key: ValueKey('profile-${p.name}'),
              value: selected.contains(p.name),
              onChanged: (v) => onChanged(p.name, v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.fromLTRB(6, 0, 14, 0),
              title: Row(
                children: [
                  Text(p.name, style: moavMono(size: 13, weight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.title,
                      style: theme.textTheme.bodySmall?.copyWith(color: MoavColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!p.recommended)
                    const StatusPill('opt-in', tone: StatusTone.neutral, dot: false),
                ],
              ),
              subtitle: Text(p.description, style: theme.textTheme.bodySmall),
            ),
          ],
        ],
      ),
    );
  }
}

class _JobView extends StatelessWidget {
  const _JobView({required this.state, required this.onReset});

  final DeployState state;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final status = s.status;
    final phase = status?.phase ?? InstallPhase.pending;
    final lines = status?.logTail ?? const <String>[];
    final progress = phase == InstallPhase.succeeded
        ? 1.0
        : (s.isRunning ? status?.progress : (status?.progress ?? 0));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: MoavCard(
            accent: true,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _PhasePill(phase: phase),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        status?.message ?? 'Waiting for the server…',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: MoavColors.text,
                            ),
                      ),
                    ),
                    if (progress != null)
                      Text(
                        '${(progress * 100).round()}%',
                        style: moavMono(size: 12, color: MoavColors.textSecondary),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _GradientProgress(value: progress),
                if (s.error != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(
                    error: s.error!,
                    trailing: s.polling ? 'Retrying automatically.' : null,
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LogView(
              lines: lines,
              title: 'deploy.log',
              highlightPrefix: '[moav-deploy]',
            ),
          ),
        ),
        if ((status?.isTerminal ?? false) || phase == InstallPhase.unknown)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onReset,
                  child: const Text('Start another install'),
                ),
              ),
            ),
          )
        else
          const SizedBox(height: 16),
      ],
    );
  }
}

/// Progress bar in the accent gradient; indeterminate when [value] is null.
class _GradientProgress extends StatelessWidget {
  const _GradientProgress({required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: const LinearProgressIndicator(minHeight: 6),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Stack(
        children: [
          Container(height: 6, color: MoavColors.borderStrong),
          FractionallySizedBox(
            widthFactor: v.clamp(0, 1),
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                gradient: MoavGradients.accent,
                boxShadow: moavGlow(blur: 8, alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhasePill extends StatelessWidget {
  const _PhasePill({required this.phase});

  final InstallPhase phase;

  @override
  Widget build(BuildContext context) {
    final (label, tone, icon) = switch (phase) {
      InstallPhase.pending => ('Starting', StatusTone.neutral, Icons.schedule),
      InstallPhase.running => ('Running', StatusTone.accent, Icons.sync),
      InstallPhase.succeeded => ('Done', StatusTone.pass, Icons.check_circle_outline),
      InstallPhase.failed => ('Failed', StatusTone.fail, Icons.error_outline),
      InstallPhase.unknown => ('Unknown', StatusTone.warn, Icons.help_outline),
    };
    return StatusPill(label, tone: tone, icon: icon);
  }
}
