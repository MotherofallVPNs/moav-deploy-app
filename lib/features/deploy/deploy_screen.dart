import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/error_view.dart';
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
      appBar: AppBar(
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
        if (s.error != null) ...[
          const SizedBox(height: 16),
          ErrorBanner(error: s.error!),
        ],
        const SizedBox(height: 24),
        GradientButton(
          onPressed: s.starting || _passwordError != null ? null : _start,
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
      ),
    );
  }
}

class _JobView extends StatefulWidget {
  const _JobView({required this.state, required this.onReset});

  final DeployState state;
  final Future<void> Function() onReset;

  @override
  State<_JobView> createState() => _JobViewState();
}

class _JobViewState extends State<_JobView> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant _JobView old) {
    super.didUpdateWidget(old);
    if (old.state.status?.logTail.length != widget.state.status?.logTail.length) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SectionHeader(
            'deploy.log',
            padding: const EdgeInsets.only(bottom: 8),
            trailing: Text(
              '${lines.length} lines',
              style: moavLabel(size: 10, color: MoavColors.textMuted),
            ),
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            decoration: BoxDecoration(
              color: MoavColors.codeBg,
              borderRadius: MoavRadius.control,
              border: Border.all(color: MoavColors.border),
            ),
            child: lines.isEmpty
                ? Center(
                    child: Text(
                      'No output yet',
                      style: moavMono(size: 12, color: MoavColors.textMuted),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: lines.length,
                    itemBuilder: (_, i) => Text(
                      lines[i],
                      style: moavMono(
                        size: 11,
                        weight: FontWeight.w400,
                        color: lines[i].startsWith('[moav-deploy]')
                            ? MoavColors.cyan
                            : MoavColors.codeText,
                        height: 1.4,
                      ),
                    ),
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
                  onPressed: widget.onReset,
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
