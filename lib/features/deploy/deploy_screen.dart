import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
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

    return Scaffold(
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Runs the MoaV installer on the server in the background. It is '
          'safe to re-run: an existing MoaV install is kept, existing users '
          'and keys are never touched, and settings below only fill values '
          'that are not configured yet.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _domain,
          decoration: const InputDecoration(
            labelText: 'Domain',
            hintText: 'vpn.example.org (blank = keep existing / domainless)',
          ),
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
          autocorrect: false,
          onChanged: (_) => setState(() {}),
        ),
        if (s.error != null) ...[
          const SizedBox(height: 16),
          Text(
            s.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: s.starting || _passwordError != null ? null : _start,
          icon: s.starting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.rocket_launch_outlined),
          label: const Text('Start install'),
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
    final scheme = Theme.of(context).colorScheme;
    final lines = status?.logTail ?? const <String>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _PhaseChip(phase: phase),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      status?.message ?? 'Waiting for the server…',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: phase == InstallPhase.succeeded
                    ? 1
                    : (s.isRunning ? status?.progress : (status?.progress ?? 0)),
              ),
              if (s.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${s.error} — will retry',
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Container(
            color: scheme.surfaceContainerLowest,
            child: lines.isEmpty
                ? const Center(child: Text('No output yet'))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: lines.length,
                    itemBuilder: (_, i) => Text(
                      lines[i],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
          ),
        ),
        if (status?.isTerminal ?? false || phase == InstallPhase.unknown)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.tonal(
                onPressed: widget.onReset,
                child: const Text('Start another install'),
              ),
            ),
          ),
      ],
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.phase});

  final InstallPhase phase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color, icon) = switch (phase) {
      InstallPhase.pending => ('Starting', scheme.secondary, Icons.schedule),
      InstallPhase.running => ('Running', scheme.primary, Icons.sync),
      InstallPhase.succeeded =>
        ('Done', scheme.primary, Icons.check_circle_outline),
      InstallPhase.failed => ('Failed', scheme.error, Icons.error_outline),
      InstallPhase.unknown => ('Unknown', scheme.outline, Icons.help_outline),
    };
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
