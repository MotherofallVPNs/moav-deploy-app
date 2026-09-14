import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  late final WebViewController _controller;
  var _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grafana'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _error = null);
              _controller.reload();
            },
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open in browser',
            onPressed: () => launchUrl(widget.url, mode: LaunchMode.externalApplication),
          ),
        ],
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Could not load Grafana: $_error', textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    const Text(
                      'Self-signed certificates are rejected by the in-app view; '
                      'use "Open in browser" and accept the certificate there.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : WebViewWidget(controller: _controller),
    );
  }
}
