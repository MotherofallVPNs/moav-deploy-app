import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_error.dart';
import '../../core/moav_cli.dart';
import '../../core/moav_controller.dart';
import '../../core/server_profile.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/error_view.dart';
import '../../widgets/moav_app_bar.dart';
import '../activity/activity_provider.dart';
import '../servers/servers_provider.dart';

/// The MoaV admin dashboard inside the app.
///
/// The panel is reached through the server's own SSH session: a loopback
/// port on this device is forwarded to `PORT_ADMIN` on the server, the
/// webview loads `https://127.0.0.1:<port>/`, and the HTTP Basic challenge
/// is answered with `ADMIN_PASSWORD` read from `/opt/moav/.env`. The
/// password lives in this State only and is dropped on dispose.
///
/// The tunnel and `.env` plumbing are generic ([MoavController.openTunnel],
/// [ServerTunnel]); Grafana can use the same path once the owner decides
/// how it should be embedded.
class AdminPanelScreen extends ConsumerStatefulWidget {
  const AdminPanelScreen({super.key, required this.profile});

  final ServerProfile profile;

  static Route<void> route(ServerProfile profile) =>
      MaterialPageRoute(builder: (_) => AdminPanelScreen(profile: profile));

  @override
  ConsumerState<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends ConsumerState<AdminPanelScreen> {
  /// Basic-auth challenges answered for the current page load; more than
  /// this means the server keeps rejecting the password.
  static const maxAuthAttempts = 3;

  ServerTunnel? _tunnel;
  AdminPanelAccess? _access;
  WebViewController? _web;
  String? _password;
  Object? _error;
  String? _authNotice;
  var _progress = 0;
  var _authAttempts = 0;
  var _opening = true;

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
    _authAttempts = 0;
    _web = null;
    if (!mounted) return;
    setState(() {});
    await previous?.close();
    final profile = widget.profile;
    final controller = ref.read(moavControllerProvider(profile.id));
    try {
      final (access, tunnel) = await ref
          .read(activityProvider.notifier)
          .run('Admin dashboard · ${profile.label}', (op) async {
        op.log('Reading ${MoavCli.adminPortKey} and '
            '${MoavCli.adminPasswordKey} from ${MoavCli.root}/.env');
        final access = await controller.adminPanelAccess();
        if (!access.enabled) {
          throw const AppError(
            AppErrorKind.invalidInput,
            'The admin dashboard is disabled on this server.',
            hint: 'Enable the admin service from the Services tab first.',
          );
        }
        op.log('Dashboard on port ${access.port}; password '
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
      setState(() {
        _access = access;
        _tunnel = tunnel;
        _password = access.password;
        _web = _buildWebView(tunnel);
        _opening = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _opening = false;
      });
    }
  }

  WebViewController? _buildWebView(ServerTunnel tunnel) {
    if (WebViewPlatform.instance == null) return null;
    final origin = tunnel.uri();
    bool isTunnel(Uri? u) =>
        u != null && u.host == origin.host && u.port == origin.port;
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(MoavColors.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => _authAttempts = 0,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onWebResourceError: (e) {
          if ((e.isForMainFrame ?? true) && mounted) {
            setState(() => _error = AppError(
                  AppErrorKind.unreachable,
                  'Could not load the admin dashboard.',
                  hint: 'The tunnel is open but the panel did not answer. '
                      'Is the admin container running?',
                  detail: e.description,
                ));
          }
        },
        // Only the tunnel origin is rendered here; links elsewhere (docs,
        // mahsaserver.com) open in the system browser.
        onNavigationRequest: (req) {
          final target = Uri.tryParse(req.url);
          if (isTunnel(target)) return NavigationDecision.navigate;
          if (target != null) {
            launchUrl(target, mode: LaunchMode.externalApplication);
          }
          return NavigationDecision.prevent;
        },
        onHttpAuthRequest: _onAuthChallenge,
        // Self-signed (or domain-issued) cert on a loopback hop that is
        // already inside the SSH session; only the tunnel origin loads here.
        onSslAuthError: (e) => e.proceed(),
      ))
      ..loadRequest(origin);
  }

  Future<void> _onAuthChallenge(HttpAuthRequest request) async {
    final tunnel = _tunnel;
    if (tunnel == null || request.host != tunnel.uri().host) {
      request.onCancel();
      return;
    }
    var password = _password;
    if (password == null) {
      password = await _askPassword();
      if (!mounted) return;
      if (password == null) {
        request.onCancel();
        setState(() => _authNotice =
            '${MoavCli.adminPasswordKey} is not set in .env; enter it to sign in.');
        return;
      }
      _password = password;
    }
    if (_authAttempts >= maxAuthAttempts) {
      request.onCancel();
      _password = null;
      setState(() => _authNotice =
          'The dashboard rejected the password from .env. Reload to try again.');
      return;
    }
    _authAttempts++;
    request.onProceed(WebViewCredential(
      user: MoavCli.adminBasicAuthUser,
      password: password,
    ));
  }

  /// Manual fallback when `.env` has no password. Memory only, like the rest.
  Future<String?> _askPassword() {
    final field = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin password'),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
    return Uri(scheme: 'https', host: widget.profile.host, port: access.port);
  }

  @override
  Widget build(BuildContext context) {
    final web = _web;
    return MoavScaffold(
      appBar: MoavAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Admin dashboard'),
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
                    if (web == null || _error != null) {
                      _open();
                    } else {
                      setState(() => _authNotice = null);
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
              'Opening a tunnel to the admin dashboard…',
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
    if (web == null || tunnel == null) {
      return _Fallback(
        tunnelUrl: tunnel?.uri(),
        publicUrl: _publicUrl,
        port: _access?.port ?? MoavCli.defaultAdminPort,
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
        Expanded(
          child: Stack(
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
          ),
        ),
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
  });

  final Uri? tunnelUrl;
  final Uri? publicUrl;
  final int port;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconBadge(Icons.admin_panel_settings_outlined, size: 56),
            const SizedBox(height: 12),
            Text(
              'Admin dashboard preview is not available here',
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              tunnelUrl == null
                  ? 'port $port on the server'
                  : '$tunnelUrl forwards to server port $port',
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
