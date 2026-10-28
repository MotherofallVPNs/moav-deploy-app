import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/donate.dart';
import '../../core/donate_cli.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/log_view.dart';
import '../../widgets/moav_app_bar.dart';
import '../operate/operate_provider.dart';
import '../operate/operate_screen.dart';
import 'donate_provider.dart';

/// Donate: what the server gives back (Psiphon Conduit, Tor Snowflake,
/// MahsaNet configs), its current stats, and the MahsaNet actions.
///
/// Lives behind the app lock like every other screen. The MahsaNet API key
/// is typed here, handed to the controller once and never kept.
class DonateScreen extends ConsumerWidget {
  const DonateScreen({super.key, required this.profile, this.openUrl = _launch});

  final ServerProfile profile;

  /// Opens an external link; injectable so widget tests can record it.
  final Future<void> Function(Uri url) openUrl;

  static Route<void> route(ServerProfile profile) =>
      MaterialPageRoute(builder: (_) => DonateScreen(profile: profile));

  static Future<void> _launch(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  static final mahsaNetDashboard = Uri.parse(DonateCli.mahsaNetDashboardUrl);
  static final mahsaNetApiKeys = Uri.parse(DonateCli.mahsaNetApiKeyUrl);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = profile.id;
    final env = ref.watch(donateEnvProvider(id));
    final overview = ref.watch(donateOverviewProvider(id));
    final envNotifier = ref.read(donateEnvProvider(id).notifier);
    final overviewNotifier = ref.read(donateOverviewProvider(id).notifier);

    ref.listen(donateActionsProvider(id), (prev, next) {
      final error = next.error;
      final text = error?.summary ?? next.message;
      if (text == null) return;
      if (next.message == prev?.message && identical(error, prev?.error)) return;
      final messenger = ScaffoldMessenger.of(context);
      if (error == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(text), duration: const Duration(seconds: 6)),
        );
        return;
      }
      final detail = error.detail;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 8),
        action: detail == null
            ? null
            : SnackBarAction(
                label: 'Details',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(error.message),
                    content: SizedBox(
                      width: double.maxFinite,
                      child: LogView(lines: detail.split('\n'), height: 260),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
      ));
    });

    Future<void> refresh() => Future.wait([
          envNotifier.refresh(),
          overviewNotifier.refresh(),
        ]);

    return StaleRefresher(
      onOpen: (ref) {
        envNotifier.refreshIfStale(tabStaleAfter);
        overviewNotifier.refreshIfStale(tabStaleAfter);
      },
      child: MoavScaffold(
        appBar: MoavAppBar(
          title: const Text('Donate'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: refresh,
            ),
          ],
        ),
        body: Column(
          children: [
            RefreshingBar(visible: env.refreshing || overview.refreshing),
            Expanded(
              child: RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    const _IntroCard(),
                    SectionHeader(
                      'Donation status',
                      trailing: updatedAt(context, overview.fetchedAt),
                    ),
                    _StatusSection(
                      state: overview,
                      onRetry: overviewNotifier.refresh,
                    ),
                    const SectionHeader('MahsaNet configs'),
                    _MahsaNetSection(
                      profile: profile,
                      env: env,
                      overview: overview.data,
                      onRetry: envNotifier.refresh,
                      openUrl: openUrl,
                    ),
                    const SectionHeader('MahsaNet dashboard'),
                    MoavCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Manage your donated configs, API keys and donor '
                            'status on the MahsaNet website.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const ValueKey('mahsanet-dashboard'),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Open MahsaNet dashboard'),
                            onPressed: () => openUrl(mahsaNetDashboard),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What donating means, in one card.
class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: MoavColors.cyan),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$title. ',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: body),
                    ],
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        );
    return MoavCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(
                Icons.volunteer_activism_outlined,
                size: 46,
                gradient: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text('Give back', style: theme.textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'MoaV can contribute bandwidth to Psiphon Conduit and Tor '
            'Snowflake, and donate generated configs to MahsaNet. Everything '
            'on this screen runs on your server through this SSH connection.',
            style: theme.textTheme.bodyMedium,
          ),
          row(
            Icons.swap_vert,
            'Psiphon Conduit',
            'Relays traffic for Psiphon users within the bandwidth cap you set.',
          ),
          row(
            Icons.ac_unit,
            'Tor Snowflake',
            'Acts as a Snowflake proxy so censored users can reach Tor.',
          ),
          row(
            Icons.share_outlined,
            'MahsaNet',
            'Creates lightweight users here and hands their share links to '
                'MahsaNet VPN.',
          ),
        ],
      ),
    );
  }
}

// --- Status ---

class _StatusSection extends StatelessWidget {
  const _StatusSection({required this.state, required this.onRetry});

  final FetchState<DonateOverview> state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    if (data == null) {
      final error = state.error;
      if (error != null && !state.loading) {
        return StaleNotice(error: error, onRetry: onRetry);
      }
      return const _Pending('Reading moav donate status…');
    }
    final s = data.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: StaleNotice(error: state.error!, onRetry: onRetry),
          ),
        _MahsaNetStatusCard(stats: s.mahsaNet, configs: data.configs),
        const SizedBox(height: 10),
        _BandwidthCard(
          icon: Icons.swap_vert,
          title: 'Psiphon Conduit',
          service: s.conduit,
          capacityNoun: 'max clients',
          startHint: 'moav start conduit',
        ),
        const SizedBox(height: 10),
        _BandwidthCard(
          icon: Icons.ac_unit,
          title: 'Tor Snowflake',
          service: s.snowflake,
          capacityNoun: 'capacity',
          startHint: 'moav start snowflake',
        ),
      ],
    );
  }
}

class _Pending extends StatelessWidget {
  const _Pending(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return MoavCard(
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _MahsaNetStatusCard extends StatelessWidget {
  const _MahsaNetStatusCard({required this.stats, required this.configs});

  final MahsaNetStats stats;
  final List<DonatedConfig> configs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, tone) = !stats.configured
        ? ('not configured', StatusTone.neutral)
        : stats.hasStats
            ? ('connected', StatusTone.pass)
            : ('unreachable', StatusTone.warn);
    return MoavCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            icon: Icons.share_outlined,
            title: 'MahsaNet',
            pill: StatusPill(label, tone: tone, dot: false),
          ),
          const SizedBox(height: 10),
          if (!stats.configured)
            Text(
              'No API key on this server yet. Add one below to start '
              'donating configs.',
              style: theme.textTheme.bodySmall,
            )
          else if (stats.hasStats) ...[
            Row(
              children: [
                _Stat('donated', '${stats.total}'),
                _Stat('active', '${stats.active ?? 0}', tone: StatusTone.pass),
                _Stat(
                  'inactive',
                  '${stats.inactive ?? 0}',
                  tone: (stats.inactive ?? 0) > 0 ? StatusTone.warn : null,
                ),
              ],
            ),
            if (configs.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              _ConfigList(configs: configs),
            ],
          ] else
            Text(
              stats.statsError ?? 'MahsaNet did not answer.',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

/// Donated configs as MahsaNet sees them: scheme, state, health, uses.
class _ConfigList extends StatelessWidget {
  const _ConfigList({required this.configs});

  final List<DonatedConfig> configs;

  @override
  Widget build(BuildContext context) {
    final mono = moavMono(size: 12, weight: FontWeight.w400);
    final dim = moavMono(size: 12, weight: FontWeight.w400, color: MoavColors.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in configs)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                SizedBox(width: 28, child: Text('${c.index}', style: dim)),
                Expanded(child: Text(c.scheme, style: mono)),
                StatusPill(
                  c.active ? 'active' : 'inactive',
                  tone: c.active ? StatusTone.pass : StatusTone.neutral,
                  dot: false,
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    c.healthPercent == null ? '' : '${c.healthPercent}%',
                    style: mono,
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    'used ${c.used}',
                    style: dim,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BandwidthCard extends StatelessWidget {
  const _BandwidthCard({
    required this.icon,
    required this.title,
    required this.service,
    required this.capacityNoun,
    required this.startHint,
  });

  final IconData icon;
  final String title;
  final BandwidthDonation service;
  final String capacityNoun;
  final String startHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, tone) = !service.enabled
        ? ('disabled', StatusTone.neutral)
        : service.running
            ? ('running', StatusTone.pass)
            : ('stopped', StatusTone.warn);
    final limits = [
      if (service.bandwidthMbps != null) '${service.bandwidthMbps} Mbps',
      if (service.maxClients != null) '${service.maxClients} $capacityNoun',
    ].join(' · ');
    final String detail;
    if (!service.enabled) {
      detail = 'Disabled in .env. Enable it from Services to donate bandwidth.';
    } else if (!service.running) {
      detail = 'Enabled but not running. Start it from Services ($startHint).';
    } else if (service.hasTraffic) {
      final who = service.connected != null
          ? '${service.connected} connected'
          : service.served != null
              ? '${service.served} people served'
              : null;
      detail = [
        ?who,
        '${service.uploaded ?? '0 B'} up / ${service.downloaded ?? '0 B'} down',
      ].join(' · ');
    } else {
      detail = 'Running. Stats appear once monitoring is up.';
    }
    return MoavCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            icon: icon,
            title: title,
            pill: StatusPill(label, tone: tone, dot: false),
          ),
          const SizedBox(height: 8),
          if (limits.isNotEmpty)
            Text(
              limits,
              style: moavMono(size: 12, weight: FontWeight.w400, color: MoavColors.textSecondary),
            ),
          const SizedBox(height: 4),
          Text(detail, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title, required this.pill});

  final IconData icon;
  final String title;
  final Widget pill;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconBadge(icon, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        pill,
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.tone});

  final String label;
  final String value;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: moavMono(size: 20, weight: FontWeight.w600, color: tone?.color ?? MoavColors.text),
          ),
          Text(label, style: moavLabel(size: 10, color: MoavColors.textMuted)),
        ],
      ),
    );
  }
}

// --- MahsaNet actions ---

/// Key form when `.env` has no `MAHSANET_API_KEY`, donate form when it does.
class _MahsaNetSection extends ConsumerWidget {
  const _MahsaNetSection({
    required this.profile,
    required this.env,
    required this.overview,
    required this.onRetry,
    required this.openUrl,
  });

  final ServerProfile profile;
  final FetchState<DonateEnv> env;
  final DonateOverview? overview;
  final Future<void> Function() onRetry;
  final Future<void> Function(Uri url) openUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = env.data;
    if (data == null) {
      final error = env.error;
      if (error != null && !env.loading) {
        return StaleNotice(error: error, onRetry: onRetry);
      }
      return const _Pending('Checking the server .env for a MahsaNet key…');
    }
    final actions = ref.watch(donateActionsProvider(profile.id));
    final notifier = ref.read(donateActionsProvider(profile.id).notifier);
    if (!data.mahsaNetKeyPresent) {
      return _KeyForm(
        busy: actions.isRunning(DonateActionKind.saveKey),
        onSave: notifier.saveKey,
        openUrl: openUrl,
      );
    }
    return _DonateForm(
      env: data,
      actions: actions,
      onDonate: (count, prefix) => notifier.donate(count: count, prefix: prefix),
    );
  }
}

class _KeyForm extends StatefulWidget {
  const _KeyForm({
    required this.busy,
    required this.onSave,
    required this.openUrl,
  });

  final bool busy;
  final Future<void> Function(String key) onSave;
  final Future<void> Function(Uri url) openUrl;

  @override
  State<_KeyForm> createState() => _KeyFormState();
}

class _KeyFormState extends State<_KeyForm> {
  final _key = TextEditingController();
  bool _show = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _key.text.trim();
    if (key.isEmpty) return;
    // The controller clears the field; the key lives on in the server's
    // .env only.
    _key.clear();
    await widget.onSave(key);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MoavCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Connect MahsaNet', style: theme.textTheme.titleMedium),
              ),
              const StatusPill('key missing', tone: StatusTone.warn, dot: false),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This server has no MahsaNet API key in its .env yet. Paste one '
            'here and moav donate setup validates it and stores it on the '
            'server. The key is not kept on this phone.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Text(
            '1. Register at mahsaserver.com and verify your email.\n'
            '2. Fill out the verified donor form.\n'
            '3. Generate an API key on the API page.',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => widget.openUrl(DonateScreen.mahsaNetApiKeys),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open the MahsaNet API page'),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('mahsanet-key-field'),
            controller: _key,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !widget.busy,
            style: moavMono(size: 13, weight: FontWeight.w400),
            decoration: InputDecoration(
              labelText: 'MahsaNet API key',
              suffixIcon: IconButton(
                tooltip: _show ? 'Hide key' : 'Show key',
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 14),
          GradientButton(
            key: const ValueKey('mahsanet-save-key'),
            icon: Icons.save_outlined,
            label: 'Validate and save key',
            busy: widget.busy,
            expand: true,
            onPressed: _key.text.trim().isEmpty ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _DonateForm extends StatefulWidget {
  const _DonateForm({
    required this.env,
    required this.actions,
    required this.onDonate,
  });

  final DonateEnv env;
  final DonateActionState actions;
  final Future<void> Function(int count, String prefix) onDonate;

  @override
  State<_DonateForm> createState() => _DonateFormState();
}

class _DonateFormState extends State<_DonateForm> {
  final _count = TextEditingController(text: '1');
  final _prefix = TextEditingController(text: DonateCli.defaultPrefix);

  @override
  void dispose() {
    _count.dispose();
    _prefix.dispose();
    super.dispose();
  }

  String? get _countError => DonateCli.validateCount(_count.text);
  String? get _prefixError => DonateCli.validatePrefix(_prefix.text.trim());

  Future<void> _confirmAndDonate() async {
    final count = int.parse(_count.text.trim());
    final prefix = _prefix.text.trim();
    final protocols = widget.env.protocols.join(', ');
    final users = count == 1 ? '1 new user' : '$count new users';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Donate $count config ${count == 1 ? 'set' : 'sets'}?'),
        content: Text(
          'Creates $users on the server named ${prefix}01 onwards with only '
          'the donated protocols ($protocols), then submits their share '
          'links to MahsaNet.\n\n'
          'The new users appear under Users; revoke them there to stop '
          'serving the configs. Withdrawing a donation from MahsaNet is done '
          'on the server with moav donate remove.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-donate'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Donate'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.onDonate(count, prefix);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = widget.actions.isRunning(DonateActionKind.donate);
    final valid = _countError == null && _prefixError == null;
    final last = widget.actions.lastResult;
    return MoavCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Generate and donate', style: theme.textTheme.titleMedium),
              ),
              const StatusPill('key set', tone: StatusTone.pass, dot: false),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The API key is stored in the server .env. Each run creates '
            'lightweight users with only the donated protocols '
            '(${widget.env.protocols.join(', ')}) and submits one share link '
            'per protocol to the ${widget.env.pool ?? DonateCli.defaultPrefix} pool.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  key: const ValueKey('donate-count'),
                  controller: _count,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: moavMono(size: 14, weight: FontWeight.w500),
                  decoration: InputDecoration(
                    labelText: 'Users',
                    helperText: '${DonateCli.minCount} to ${DonateCli.maxCount}',
                    errorText: _count.text.isEmpty ? null : _countError,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('donate-prefix'),
                  controller: _prefix,
                  enabled: !busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: moavMono(size: 14, weight: FontWeight.w500),
                  decoration: InputDecoration(
                    labelText: 'Username prefix',
                    helperText: 'Users become ${_prefix.text.trim()}01, 02…',
                    errorText: _prefixError,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GradientButton(
            key: const ValueKey('donate-run'),
            icon: Icons.volunteer_activism_outlined,
            label: busy ? 'Donating…' : 'Generate and donate',
            busy: busy,
            expand: true,
            onPressed: valid ? _confirmAndDonate : null,
          ),
          if (last != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last run: ${DonateActionsNotifier.describe(last)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
