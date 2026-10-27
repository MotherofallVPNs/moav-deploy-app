import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_error.dart';

/// Signs in to Grafana through the SSH tunnel and hands back the session
/// cookies for the webview.
///
/// Grafana has no Basic-auth challenge for its UI (the SPA redirects to
/// `/login`), so the credentials are posted to `POST /login` the way the
/// login form does; the `grafana_session` cookies that come back are the
/// whole session. The password is used for this one request and is never
/// logged, stored, or put into an error.
class GrafanaLogin {
  GrafanaLogin._();

  static const loginPath = '/login';
  static const timeout = Duration(seconds: 20);

  /// Posts [user]/[password] to `[origin]/login`; returns the cookies to
  /// install. Throws [GrafanaLoginRejected] on a 401 and [AppError] when
  /// Grafana cannot be reached or answers something else.
  ///
  /// [origin] must be the tunnel origin (`https://127.0.0.1:<port>`); the
  /// certificate check is relaxed for that loopback host only, because the
  /// hop is already inside the SSH session.
  static Future<List<Cookie>> signIn(
    Uri origin, {
    required String user,
    required String password,
    HttpClient? client,
  }) async {
    final http = client ?? HttpClient();
    http.badCertificateCallback =
        (cert, host, port) => host == origin.host && port == origin.port;
    try {
      final request = await http
          .postUrl(origin.replace(path: loginPath))
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode({'user': user, 'password': password}));
      final response = await request.close().timeout(timeout);
      // Drain the body so the connection can be reused or closed cleanly.
      await response.drain<void>().catchError((_) {});
      switch (response.statusCode) {
        case HttpStatus.ok:
          return response.cookies;
        case HttpStatus.unauthorized:
          throw const GrafanaLoginRejected();
        default:
          throw AppError(
            AppErrorKind.unreachable,
            'Grafana did not accept the sign-in request.',
            hint: 'The tunnel is open but Grafana answered HTTP '
                '${response.statusCode}. Is the monitoring profile running?',
          );
      }
    } on GrafanaLoginRejected {
      rethrow;
    } on AppError {
      rethrow;
    } on Object catch (e) {
      throw AppError(
        AppErrorKind.unreachable,
        'Could not reach Grafana through the tunnel.',
        hint: 'Is the monitoring profile running on the server?',
        detail: e.toString(),
      );
    } finally {
      if (client == null) http.close(force: true);
    }
  }
}

/// Grafana answered 401: the password from `.env` is not the one Grafana
/// was started with (it is read once at container start).
class GrafanaLoginRejected implements Exception {
  const GrafanaLoginRejected();

  @override
  String toString() => 'Grafana rejected the admin password';
}
