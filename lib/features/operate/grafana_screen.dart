import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_error.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/error_view.dart';

/// Grafana embedded in a webview. Login is Grafana's own; nothing is stored.
class GrafanaScreen extends StatefulWidget {
  const GrafanaScreen({super.key, required this.url});

  final Uri url;

  static Route<void> route(Uri url) =>
      MaterialPageRoute(builder: (_) => GrafanaScreen(url: url));

  @override
  State<GrafanaScreen> createState() => _GrafanaScreenState();
}

class _GrafanaScreenState extends State<GrafanaScreen> {
  final _panel = GlobalKey<GrafanaPanelState>();

  @override
  Widget build(BuildContext context) {
    return MoavScaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Grafana'),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.url.host,
                style: moavMono(size: 12, color: MoavColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: () => _panel.currentState?.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open in browser',
            onPressed: () => launchUrl(widget.url, mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: GrafanaPanel(key: _panel, url: widget.url),
    );
  }
}

/// The webview itself, reusable inline (analytics tab) and full screen.
///
/// Falls back to a placeholder when no webview platform is registered (unit
/// tests, unsupported hosts) and to an error view with the open-in-browser
/// hint when the page fails to load (typically a self-signed certificate).
class GrafanaPanel extends StatefulWidget {
  const GrafanaPanel({super.key, required this.url, this.compact = false});

  final Uri url;

  /// Smaller error/placeholder layout for the inline card.
  final bool compact;

  @override
  State<GrafanaPanel> createState() => GrafanaPanelState();
}

class GrafanaPanelState extends State<GrafanaPanel> {
  WebViewController? _controller;
  var _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (WebViewPlatform.instance == null) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(MoavColors.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) {
            setState(() => _error = e.description);
          }
        },
      ))
      ..loadRequest(widget.url);
  }

  void reload() {
    setState(() => _error = null);
    _controller?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return _Fallback(url: widget.url, compact: widget.compact);
    if (_error != null) {
      final error = AppError(
        AppErrorKind.unreachable,
        'Could not load Grafana.',
        hint: 'Self-signed certificates are rejected by the in-app view; '
            'use "Open in browser" and accept the certificate there.',
        detail: _error,
      );
      if (widget.compact) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ErrorBanner(error: error),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(widget.url, mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: const Text('Open in browser'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: reload, child: const Text('Retry')),
                ],
              ),
            ],
          ),
        );
      }
      return ErrorView(error: error, onRetry: reload);
    }
    return Stack(
      children: [
        WebViewWidget(controller: controller),
        if (_progress < 100)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.url, required this.compact});

  final Uri url;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(Icons.dashboard_outlined, size: compact ? 40 : 56),
            const SizedBox(height: 12),
            Text(
              'Grafana preview is not available here',
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              url.toString(),
              style: moavMono(size: 11, color: MoavColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => launchUrl(url, mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_browser, size: 18),
              label: const Text('Open in browser'),
            ),
          ],
        ),
      ),
    );
  }
}
