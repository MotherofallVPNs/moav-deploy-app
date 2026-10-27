import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moav_deploy/core/app_error.dart';
import 'package:moav_deploy/core/grafana_login.dart';

/// A loopback stand-in for Grafana's `POST /login`.
class FakeGrafana {
  FakeGrafana(this.server) {
    server.listen(_handle);
  }

  final HttpServer server;
  final requests = <({String path, String method, Map<String, Object?> body})>[];
  int status = HttpStatus.ok;

  static Future<FakeGrafana> start() async =>
      FakeGrafana(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  Uri get origin => Uri(scheme: 'http', host: '127.0.0.1', port: server.port);

  Future<void> _handle(HttpRequest req) async {
    final text = await utf8.decoder.bind(req).join();
    requests.add((
      path: req.uri.path,
      method: req.method,
      body: text.isEmpty ? {} : (jsonDecode(text) as Map).cast<String, Object?>(),
    ));
    req.response.statusCode = status;
    if (status == HttpStatus.ok) {
      req.response.cookies
        ..add(Cookie('grafana_session', 'abc123')
          ..path = '/'
          ..httpOnly = true)
        ..add(Cookie('grafana_session_expiry', '1761584400')..path = '/');
      req.response.write('{"message":"Logged in","redirectUrl":"/"}');
    } else {
      req.response.write('{"message":"invalid username or password"}');
    }
    await req.response.close();
  }

  Future<void> close() => server.close(force: true);
}

void main() {
  late FakeGrafana grafana;
  setUp(() async => grafana = await FakeGrafana.start());
  tearDown(() => grafana.close());

  test('posts the login form JSON and returns the session cookies', () async {
    final cookies = await GrafanaLogin.signIn(
      grafana.origin,
      user: 'admin',
      password: 'pw-with-"quotes"',
    );
    expect(grafana.requests.single.method, 'POST');
    expect(grafana.requests.single.path, '/login');
    expect(grafana.requests.single.body,
        {'user': 'admin', 'password': 'pw-with-"quotes"'});
    expect(cookies.map((c) => c.name), ['grafana_session', 'grafana_session_expiry']);
    expect(cookies.first.value, 'abc123');
  });

  test('401 is a rejection that never carries the password', () async {
    grafana.status = HttpStatus.unauthorized;
    await expectLater(
      GrafanaLogin.signIn(grafana.origin, user: 'admin', password: 'hunter2'),
      throwsA(isA<GrafanaLoginRejected>()
          .having((e) => e.toString(), 'text', isNot(contains('hunter2')))),
    );
  });

  test('other statuses and a dead port become AppErrors', () async {
    grafana.status = HttpStatus.badGateway;
    await expectLater(
      GrafanaLogin.signIn(grafana.origin, user: 'admin', password: 'pw'),
      throwsA(isA<AppError>()
          .having((e) => e.kind, 'kind', AppErrorKind.unreachable)
          .having((e) => e.hint, 'hint', contains('502'))),
    );
    final dead = grafana.origin;
    await grafana.close();
    await expectLater(
      GrafanaLogin.signIn(dead, user: 'admin', password: 'pw'),
      throwsA(isA<AppError>()
          .having((e) => e.message, 'message', contains('Could not reach'))
          .having((e) => e.toString(), 'text', isNot(contains('pw')))),
    );
    grafana = await FakeGrafana.start();
  });
}
