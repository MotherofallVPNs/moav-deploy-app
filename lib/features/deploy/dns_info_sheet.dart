import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_error.dart';
import '../../core/dns_check.dart';
import '../../core/dns_records.dart';
import '../../core/moav_controller.dart';
import '../../core/moav_links.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/error_view.dart';
import '../servers/servers_provider.dart';

/// Opens the DNS-records popup for a domain install: the records to create,
/// the `dns-records.txt` to download or copy, and a live check.
Future<void> showDnsInfoSheet(
  BuildContext context, {
  required ServerProfile profile,
  required String domain,
}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        maxChildSize: 0.96,
        minChildSize: 0.4,
        builder: (_, scroll) => DnsInfoSheet(
          profile: profile,
          domain: domain,
          scrollController: scroll,
        ),
      ),
    );

/// Hands the zone text to the platform share sheet as `dns-records.txt`,
/// the same temp-file-for-the-sheet's-lifetime contract as the bundle zip.
class DnsZoneSharer {
  const DnsZoneSharer();

  Future<void> share(String text, {required String domain, Rect? origin}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${DnsRecords.fileName}');
    await file.writeAsString(text, flush: true);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(file.path, mimeType: 'text/plain', name: DnsRecords.fileName),
          ],
          subject: 'MoaV DNS records ($domain)',
          sharePositionOrigin: origin,
        ),
      );
    } finally {
      if (await file.exists()) await file.delete();
    }
  }
}

/// Overridden in widget tests to capture what would have been shared.
final dnsZoneSharerProvider =
    Provider<DnsZoneSharer>((_) => const DnsZoneSharer());

/// Body of the DNS popup. Resolves the server's public IP over the existing
/// SSH session on open; "Verify DNS" asks the server to look the records up.
/// Nothing here gates the install.
class DnsInfoSheet extends ConsumerStatefulWidget {
  const DnsInfoSheet({
    super.key,
    required this.profile,
    required this.domain,
    this.scrollController,
    this.onOpen = _launch,
  });

  final ServerProfile profile;
  final String domain;
  final ScrollController? scrollController;

  /// Injectable so tests can record which link a button opens.
  final Future<void> Function(Uri url) onOpen;

  static Future<void> _launch(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  ConsumerState<DnsInfoSheet> createState() => _DnsInfoSheetState();
}

class _DnsInfoSheetState extends ConsumerState<DnsInfoSheet> {
  String? _ip;
  bool _resolving = false;
  AppError? _ipError;

  DnsCheckReport? _report;
  bool _checking = false;
  AppError? _checkError;

  String get _domain => DnsRecords.normalizeDomain(widget.domain);

  MoavController get _controller =>
      ref.read(moavControllerProvider(widget.profile.id));

  @override
  void initState() {
    super.initState();
    _resolveIp();
  }

  Future<void> _resolveIp() async {
    setState(() {
      _resolving = true;
      _ipError = null;
    });
    String? ip;
    AppError? error;
    try {
      ip = await _controller.publicIp();
    } on Object catch (e) {
      error = AppError.from(e, host: widget.profile.host, port: widget.profile.port);
    }
    // A profile addressed by IP still gets its records when SSH is down.
    ip ??= PublicIp.isLiteralV4(widget.profile.host) ? widget.profile.host : null;
    if (!mounted) return;
    setState(() {
      _ip = ip;
      _resolving = false;
      _ipError = ip == null ? (error ?? _noIpError) : null;
    });
  }

  static final _noIpError = AppError.from(
    StateError('The server did not report a public IPv4 address'),
  );

  Future<void> _verify() async {
    final ip = _ip;
    if (ip == null || _checking) return;
    setState(() {
      _checking = true;
      _checkError = null;
    });
    DnsCheckReport? report;
    AppError? error;
    try {
      report = await _controller.checkDns(domain: _domain, serverIp: ip);
    } on Object catch (e) {
      error = AppError.from(e, host: widget.profile.host, port: widget.profile.port);
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _report = report ?? _report;
      _checkError = error;
    });
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('DNS records copied')),
    );
  }

  Future<void> _download(BuildContext buttonContext, String text) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(dnsZoneSharerProvider)
          .share(text, domain: _domain, origin: origin);
    } on Object catch (e) {
      showErrorSnackBar(messenger, e, prefix: 'Could not save the file.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final domain = _domain;
    final ip = _ip;
    final validDomain = DnsRecords.isValidDomain(domain);
    final records = DnsRecords.forDomain(domain, ip ?? 'SERVER_IP');
    final zone = ip == null ? null : DnsRecords.zoneFile(domain, ip);
    final report = _report;
    final resultFor = <String, DnsRecordCheck>{
      if (report != null)
        for (final c in report.checks) '${c.record.type} ${c.record.name}': c,
    };

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Row(
          children: [
            const IconBadge(Icons.dns_outlined, gradient: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DNS records', style: theme.textTheme.titleLarge),
                  Text(domain, style: moavMono(size: 13, color: MoavColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Create these records at your DNS provider before you start. The '
          'installer asks Let\'s Encrypt for a certificate for the domain, '
          'which only works once the name points at this server. The NS '
          'records delegate the DNS-tunnel subdomains to the server itself.',
          style: theme.textTheme.bodyMedium,
        ),
        if (!validDomain) ...[
          const SizedBox(height: 12),
          ErrorBanner(
            error: AppError.from(
              StateError('"$domain" does not look like a hostname'),
            ),
          ),
        ],
        const SectionHeader('Server IP'),
        _ServerIpCard(
          ip: ip,
          resolving: _resolving,
          error: _ipError,
          onRetry: _resolveIp,
        ),
        const SectionHeader('Records'),
        MoavCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, r) in records.indexed) ...[
                if (i > 0) const Divider(),
                _RecordRow(
                  key: ValueKey('dns-record-${r.type}-${r.name}'),
                  record: r,
                  check: resultFor['${r.type} ${r.name}'],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('dns-copy'),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
                onPressed: zone == null ? null : () => _copy(zone),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Builder(
                builder: (ctx) => OutlinedButton.icon(
                  key: const ValueKey('dns-download'),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Download'),
                  onPressed: zone == null ? null : () => _download(ctx, zone),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GradientButton(
          key: const ValueKey('dns-verify'),
          onPressed: ip == null || !validDomain ? null : _verify,
          busy: _checking,
          expand: true,
          icon: Icons.fact_check_outlined,
          label: report == null ? 'Verify DNS' : 'Verify again',
        ),
        if (_checkError != null) ...[
          const SizedBox(height: 10),
          ErrorBanner(error: _checkError!),
        ],
        if (report != null) ...[
          const SizedBox(height: 10),
          _ReportCard(report: report),
        ],
        const SizedBox(height: 14),
        Text(
          'Guidance only: the install starts without this check, and MoaV '
          'repeats it on the server as "moav doctor dns". Save the file as '
          '$_fileName and import it, or create the records by hand.',
          style: theme.textTheme.bodySmall,
        ),
        if (zone != null) ...[
          const SectionHeader('dns-records.txt'),
          CodeBlock(zone, size: 11),
        ],
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('DNS guide on moav.sh'),
            onPressed: () => widget.onOpen(MoavLinks.docsDns),
          ),
        ),
      ],
    );
  }

  static const _fileName = DnsRecords.fileName;
}

class _ServerIpCard extends StatelessWidget {
  const _ServerIpCard({
    required this.ip,
    required this.resolving,
    required this.error,
    required this.onRetry,
  });

  final String? ip;
  final bool resolving;
  final AppError? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget body;
    if (resolving) {
      body = Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 10),
          Text('Asking the server for its public IP…',
              style: theme.textTheme.bodySmall),
        ],
      );
    } else if (ip != null) {
      body = Row(
        children: [
          Expanded(
            child: Text(
              ip!,
              key: const ValueKey('dns-server-ip'),
              style: moavMono(size: 15, weight: FontWeight.w600),
            ),
          ),
          const StatusPill('from server', tone: StatusTone.accent, dot: false),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error?.summary ?? 'Could not determine the public IP.',
            style: theme.textTheme.bodySmall?.copyWith(color: MoavColors.fail),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Try again'),
            ),
          ),
        ],
      );
    }
    return MoavCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          body,
          const SizedBox(height: 6),
          Text(
            'Every A record below points here. Both A records must stay '
            '"DNS only" (grey cloud) on Cloudflare.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({super.key, required this.record, this.check});

  final DnsRecord record;
  final DnsRecordCheck? check;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = check;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(record.type, tone: StatusTone.neutral, dot: false),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  record.name,
                  style: moavMono(size: 13, weight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (record.optional && c == null)
                const StatusPill('opt-in', tone: StatusTone.neutral, dot: false),
              if (c != null) StatusPill.result(c.result),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            record.value,
            style: moavMono(size: 12, color: MoavColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            c == null ? record.comment : c.detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: c == null ? null : StatusToneX.of(c.result).color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final DnsCheckReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tool = report.tool;
    return MoavCard(
      key: const ValueKey('dns-report'),
      accent: report.ready,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusPill.result(
            report.overall,
            label: report.ready ? 'ready' : report.overall.name,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(report.summary, style: theme.textTheme.bodyMedium),
                if (tool != null)
                  Text(
                    'Checked from the server with $tool.',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
