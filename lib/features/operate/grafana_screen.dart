import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_error.dart';
import '../../core/grafana_login.dart';
import '../../core/moav_cli.dart';
import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/error_view.dart';
import '../../widgets/moav_app_bar.dart';
import '../activity/activity_provider.dart';
import '../servers/servers_provider.dart';

/// Posts the credentials to Grafana over the tunnel; see [GrafanaLogin.signIn].
typedef GrafanaSignIn = Future<List<Cookie>> Function(
  Uri origin, {
  required String user,
  required String password,
});

/// Overridden in widget tests, where no Grafana listens on the tunnel.
final grafanaSignInProvider =
    Provider<GrafanaSignIn>((_) => GrafanaLogin.signIn);

/// Grafana inside the app, reached the same way as the admin dashboard: a
/// loopback port on this device is forwarded over SSH to `PORT_GRAFANA`
/// on the server, the app signs in with `ADMIN_PASSWORD` from
/// `/opt/moav/.env` (Grafana's `GF_SECURITY_ADMIN_PASSWORD`), and the
/// webview loads the tunnel origin with the session cookies installed.
/// Grafana's public port is never used; the password lives in this State
/// only and is dropped on dispose.
class GrafanaScreen extends ConsumerStatefulWidget {
  const GrafanaScreen({super.key, required this.profile});

  final ServerProfile profile;

  static Route<void> route(ServerProfile profile) =>
      MaterialPageRoute(builder: (_) => GrafanaScreen(profile: profile));

  @override
  ConsumerState<GrafanaScreen> createState() => _GrafanaScreenState();
}

class _GrafanaScreenState extends ConsumerState<GrafanaScreen> {
  ServerTunnel? _tunnel;
  GrafanaAccess? _access;
  WebViewController? _web;
  String? _password;
  Object? _error;
  String? _authNotice;
  var _progress = 0;
  var _opening = true;
  var _signedIn = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: the activity entry must not change providers
    // while the route is still being built.
    Future<void>.microtask(_open);
  }

  @override
  void dispose() {
    _password = null;
    _tunnel?.close();
    super.dispose();
  }

  Future<void> _open() async {
    final previous = _tunnel;
    _tunnel = null;
    _opening = true;
    _error = null;
    _authNotice = null;
    _signedIn = false;
    _web = null;
    if (!mounted) return;
    setState(() {});
    await previous?.close();
    final profile = widget.profile;
    final controller = ref.read(moavControllerProvider(profile.id));
    try {
      final (access, tunnel) = await ref
          .read(activityProvider.notifier)
          .run('Grafana · ${profile.label}', (op) async {
        op.log('Reading ${MoavCli.grafanaPortKey} and '
            '${MoavCli.grafanaPasswordKey} from ${MoavCli.root}/.env');
        final access = await controller.grafanaAccess();
        if (!access.enabled) {
          throw const AppError(
            AppErrorKind.invalidInput,
            'Monitoring is disabled on this server.',
            hint: 'Enable the monitoring profile from the Services tab first.',
          );
        }
        op.log('Grafana on port ${access.port} (${access.scheme}); password '
            '${access.password == null ? 'not set in .env' : 'read'}');
        final tunnel = await controller.openTunnel(access.port);
        op.log('Forwarding 127.0.0.1:${tunnel.localPort} on this device '
            'to 127.0.0.1:${access.port} on the server');
        return (access, tunnel);
      });
      if (!mounted) {
        await tunnel.close();
        return;
      }
      _access = access;
      _tunnel = tunnel;
      _password = access.password;
      await _signInAndLoad();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _opening = false;
      });
    }
  }

  Uri get _origin => _tunnel!.uri(scheme: _access!.scheme);

  /// Signs in over the tunnel, installs the cookies and loads Grafana. A
  /// missing or rejected password falls back to asking for it; declining
  /// still shows Grafana's own login form.
  Future<void> _signInAndLoad() async {
    final origin = _origin;
    var password = _password;
    password ??= await _askPassword();
    if (!mounted) return;
    if (password != null) {
      try {
        final cookies = await ref.read(grafanaSignInProvider)(
          origin,
          user: MoavCli.grafanaAdminUser,
          password: password,
        );
        await _installCookies(cookies);
        _password = password;
        _signedIn = true;
      } on GrafanaLoginRejected {
        _password = null;
        _authNotice = 'Grafana rejected the password from .env. Grafana '
            'reads it when the container starts; restart monitoring after '
            'changing it, or sign in below.';
      }
    } else {
      _authNotice =
          '${MoavCli.grafanaPasswordKey} is not set in .env; sign in below.';
    }
    if (!mounted) return;
    setState(() {
      _web = _buildWebView(origin);
      _opening = false;
    });
  }

  Future<void> _installCookies(List<Cookie> cookies) async {
    if (WebViewPlatform.instance == null) return;
    final manager = WebViewCookieManager();
    for (final c in cookies) {
      await manager.setCookie(WebViewCookie(
        name: c.name,
        value: c.value,
        domain: _origin.host,
        path: c.path ?? '/',
      ));
    }
  }

  WebViewController? _buildWebView(Uri origin) {
    if (WebViewPlatform.instance == null) return null;
    bool isTunnel(Uri? u) =>
        u != null && u.host == origin.host && u.port == origin.port;
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(MoavColors.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onWebResourceError: (e) {
          if ((e.isForMainFrame ?? true) && mounted) {
            setState(() => _error = AppError(
                  AppErrorKind.unreachable,
                  'Could not load Grafana.',
                  hint: 'The tunnel is open but Grafana did not answer. '
                      'Is the monitoring profile running?',
                  detail: e.description,
                ));
          }
        },
        // Only the tunnel origin is rendered here; links elsewhere (Grafana
        // docs, the CDN root URL) open in the system browser.
        onNavigationRequest: (req) {
          final target = Uri.tryParse(req.url);
          if (isTunnel(target)) return NavigationDecision.navigate;
          if (target != null) {
            launchUrl(target, mode: LaunchMode.externalApplication);
          }
          return NavigationDecision.prevent;
        },
        // Self-signed (or domain-issued) cert on a loopback hop that is
        // already inside the SSH session; only the tunnel origin loads here.
        onSslAuthError: (e) => e.proceed(),
      ))
      ..loadRequest(origin);
  }

  /// Manual fallback when `.env` has no usable password. Memory only.
  Future<String?> _askPassword() {
    final field = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Grafana admin password'),
        content: TextField(
          controller: field,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Skip')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, field.text),
            child: const Text('Sign in'),
          ),
        ],
      ),
    ).whenComplete(field.dispose);
  }

  Uri? get _publicUrl {
    final access = _access;
    if (access == null) return null;
    return Uri(
        scheme: access.scheme, host: widget.profile.host, port: access.port);
  }

  @override
  Widget build(BuildContext context) {
    final web = _web;
    return MoavScaffold(
      appBar: MoavAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Grafana'),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.profile.label,
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
            onPressed: _opening
                ? null
                : () {
                    if (web == null || _error != null || !_signedIn) {
                      _open();
                    } else {
                      web.reload();
                    }
                  },
          ),
          if (_publicUrl != null)
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: 'Open in browser',
              onPressed: () =>
                  launchUrl(_publicUrl!, mode: LaunchMode.externalApplication),
            ),
        ],
      ),
      body: _body(context, web),
    );
  }

  Widget _body(BuildContext context, WebViewController? web) {
    if (_opening) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Opening a tunnel to Grafana…',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return ErrorView(error: error, onRetry: _open);
    }
    final tunnel = _tunnel;
    final Widget content;
    if (web == null || tunnel == null) {
      content = _Fallback(
        tunnelUrl: tunnel == null ? null : _origin,
        publicUrl: _publicUrl,
        port: _access?.port ?? MoavCli.defaultGrafanaPort,
        signedIn: _signedIn,
      );
    } else {
      content = Stack(
        children: [
          WebViewWidget(controller: web),
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
    return Column(
      children: [
        if (_authNotice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ErrorBanner(
              error: AppError(AppErrorKind.auth, _authNotice!),
            ),
          ),
        Expanded(child: content),
      ],
    );
  }
}

/// Shown where no webview platform is registered (unit tests, unsupported
/// hosts): the tunnel is open, so say where it points and offer the browser.
class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.tunnelUrl,
    required this.publicUrl,
    required this.port,
    required this.signedIn,
  });

  final Uri? tunnelUrl;
  final Uri? publicUrl;
  final int port;
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconBadge(Icons.dashboard_outlined, size: 56),
            const SizedBox(height: 12),
            Text(
              'Grafana preview is not available here',
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              tunnelUrl == null
                  ? 'port $port on the server'
                  : '$tunnelUrl forwards to server port $port'
                      '${signedIn ? ' (signed in)' : ''}',
              style: moavMono(size: 11, color: MoavColors.textMuted),
              textAlign: TextAlign.center,
            ),
            if (publicUrl != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    launchUrl(publicUrl!, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: const Text('Open in browser'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
