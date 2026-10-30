import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/moav_controller.dart';
import '../../core/moav_services.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/moav_app_bar.dart';
import '../../widgets/error_view.dart';
import '../../widgets/log_view.dart';
import '../server/server_screen.dart';
import 'deploy_provider.dart';
import 'dns_info_sheet.dart';
import 'install_inputs.dart';

/// Deploy MoaV on a server: collects installer inputs, launches the detached
/// install, and streams the server-side log with live status.
class DeployScreen extends ConsumerWidget {
  const DeployScreen({super.key, required this.profile, this.fromServer = false});

  final ServerProfile profile;

  /// True when the server hub is the route below, so "Go to the server"
  /// returns to it instead of opening a second one.
  final bool fromServer;

  static Route<void> route(ServerProfile profile, {bool fromServer = false}) =>
      MaterialPageRoute(
        builder: (_) => DeployScreen(profile: profile, fromServer: fromServer),
      );

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
          ? _InstallForm(profile: profile, state: state, onStart: notifier.start)
          : _JobView(
              state: state,
              onReset: notifier.reset,
              onGoToServer: () => _goToServer(context),
            ),
    );
  }

  void _goToServer(BuildContext context) {
    final nav = Navigator.of(context);
    if (fromServer) {
      nav.pop();
    } else {
      nav.pushReplacement(ServerScreen.route(profile));
    }
  }
}

class _InstallForm extends StatefulWidget {
  const _InstallForm({
    required this.profile,
    required this.state,
    required this.onStart,
  });

  final ServerProfile profile;
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

  bool _advanced = false;
  bool _showPassword = false;

  /// False once the user typed an email; until then it follows the domain.
  bool _emailFollowsDomain = true;

  @override
  void dispose() {
    _domain.dispose();
    _email.dispose();
    _password.dispose();
    _branch.dispose();
    super.dispose();
  }

  /// Upstream install.sh's own rules (ni_validate): it fails the install on
  /// anything shorter than 12 or containing quotes, \ $ ` # or whitespace.
  String? get _passwordError {
    final p = _password.text;
    if (p.contains(RegExp('["\'\\\\\$`#\\s]'))) {
      return 'Avoid quotes, \\ \$ ` # and spaces in the admin password';
    }
    if (p.isNotEmpty && p.length < 12) {
      return 'At least 12 characters';
    }
    return null;
  }

  bool get _defaultProfiles =>
      _profiles.length == MoavProfiles.defaults.length &&
      _profiles.containsAll(MoavProfiles.defaults);

  void _onDomainChanged(String value) {
    if (_emailFollowsDomain) _email.text = InstallInputs.defaultEmail(value);
    setState(() {});
  }

  void _generatePassword() {
    _password.text = InstallInputs.generatePassword();
    setState(() => _showPassword = true);
  }

  /// The DNS popup: records to create, dns-records.txt, live check. Never
  /// gates [_start]; the button is disabled for a domainless install.
  void _showDnsInfo() => showDnsInfoSheet(
        context,
        profile: widget.profile,
        domain: _domain.text,
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final theme = Theme.of(context);
    final domainless = _domain.text.trim().isEmpty;
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
                    Text('Set up MoaV', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Runs the MoaV installer on the server in the background. '
                      'Safe to re-run: an existing install is kept and users '
                      'and keys are never touched.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('Setup'),
        TextField(
          controller: _domain,
          decoration: InputDecoration(
            labelText: 'Domain',
            hintText: 'vpn.example.org',
            helperText: domainless
                ? 'Optional. Blank installs by IP only (domainless mode).'
                : 'Certificates from Let\'s Encrypt for this domain. Tap the '
                    'info button for the DNS records to create first.',
            helperMaxLines: 2,
            suffixIcon: IconButton(
              key: const ValueKey('dns-info'),
              tooltip: 'DNS records for this domain',
              icon: const Icon(Icons.info_outline, size: 20),
              onPressed: domainless ? null : _showDnsInfo,
            ),
          ),
          style: moavMono(size: 14),
          keyboardType: TextInputType.url,
          autocorrect: false,
          onChanged: _onDomainChanged,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          decoration: InputDecoration(
            labelText: 'Admin dashboard password',
            helperText: 'At least 12 characters. Needed to open the admin panel.',
            helperMaxLines: 2,
            errorText: _passwordError,
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              icon: Icon(
                _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          style: _showPassword ? moavMono(size: 14) : null,
          obscureText: !_showPassword,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {}),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _generatePassword,
            icon: const Icon(Icons.casino_outlined, size: 16),
            label: const Text('Generate random'),
          ),
        ),
        const SizedBox(height: 4),
        _AdvancedToggle(
          value: _advanced,
          onChanged: (v) => setState(() => _advanced = v),
        ),
        if (_advanced) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            decoration: const InputDecoration(
              labelText: "Let's Encrypt email",
              helperText: 'Certificate notices. Defaults to info@ your domain.',
              helperMaxLines: 2,
            ),
            style: moavMono(size: 14),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onChanged: (_) => setState(() => _emailFollowsDomain = false),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _branch,
            decoration: const InputDecoration(
              labelText: 'MoaV branch',
              hintText: 'main',
              helperText: 'Git branch of MoaV to install. Leave on main.',
            ),
            style: moavMono(size: 14),
            autocorrect: false,
            onChanged: (_) => setState(() {}),
          ),
          SectionHeader(
            'Services',
            trailing: TextButton(
              onPressed: _defaultProfiles
                  ? null
                  : () => setState(() => _profiles
                    ..clear()
                    ..addAll(MoavProfiles.defaults)),
              child: const Text('Reset to default'),
            ),
          ),
          Text(
            'Passed to the MoaV installer as ENABLE_* flags for a .env this '
            'install creates; without a domain the installer turns off the '
            'certificate-dependent ones itself. Change them later from the '
            'Services tab.',
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
    final domain = _domain.text.trim();
    final email = _email.text.trim();
    widget.onStart(
      InstallSpec(
        domain: domain,
        email: email.isEmpty ? InstallInputs.defaultEmail(domain) : email,
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

/// "Advanced" row with a switch: email, branch and the service list live
/// behind it so the default install is two fields and one tap.
class _AdvancedToggle extends StatelessWidget {
  const _AdvancedToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MoavCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          const Icon(Icons.tune, size: 18, color: MoavColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Advanced', style: theme.textTheme.titleSmall),
                Text(
                  'Email, MoaV branch and service selection',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Switch(
            key: const ValueKey('advanced-toggle'),
            value: value,
            onChanged: onChanged,
          ),
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
  const _JobView({
    required this.state,
    required this.onReset,
    required this.onGoToServer,
  });

  final DeployState state;
  final Future<void> Function() onReset;
  final VoidCallback onGoToServer;

  /// What each step is doing, for the line under the step title.
  static String? hintFor(InstallStatus? status) {
    if (status == null || status.phase != InstallPhase.running) return null;
    return switch (status.step) {
      1 => 'Checking the server and any existing install.',
      2 => 'Installing packages and Docker, cloning MoaV and writing .env.',
      3 => 'Building the Docker images, then keys, certificates and the first '
          'user. This is the longest step, usually several minutes.',
      4 => 'Starting the services.',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final status = s.status;
    final phase = status?.phase ?? InstallPhase.pending;
    final lines = status?.logTail ?? const <String>[];
    final progress = phase == InstallPhase.succeeded
        ? 1.0
        : (s.isRunning ? s.progress : (s.progress ?? 0));
    final title = status == null
        ? 'Starting the install job…'
        : status.message ?? (phase == InstallPhase.pending ? 'Starting…' : '');
    final hint = hintFor(status);
    final theme = Theme.of(context);

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
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
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
                if (hint != null) ...[
                  const SizedBox(height: 6),
                  Text(hint, style: theme.textTheme.bodySmall),
                ],
                if (s.waitingForServer) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Waiting for the server…',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: MoavColors.textSecondary),
                      ),
                    ],
                  ),
                ],
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
        if (phase == InstallPhase.succeeded)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  GradientButton(
                    onPressed: onGoToServer,
                    expand: true,
                    icon: Icons.dns_outlined,
                    label: 'Go to the server',
                  ),
                  TextButton(
                    onPressed: onReset,
                    child: const Text('Start another install'),
                  ),
                ],
              ),
            ),
          )
        else if (phase == InstallPhase.failed || phase == InstallPhase.unknown)
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
