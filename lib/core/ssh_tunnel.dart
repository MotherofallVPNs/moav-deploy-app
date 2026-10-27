import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import 'moav_controller.dart';

/// A loopback listener on this device whose connections are forwarded over
/// the SSH session to a port on the server (`ssh -L`). Used to load
/// server-local web UIs such as the admin dashboard in a webview; Grafana
/// can reuse it as is.
class SshTunnel implements ServerTunnel {
  SshTunnel._(this._server, this._client, this.remoteHost, this.remotePort);

  final ServerSocket _server;
  final SSHClient _client;
  final String remoteHost;
  final int remotePort;
  final _channels = <SSHForwardChannel>{};
  var _closed = false;

  /// Binds an ephemeral port on 127.0.0.1 and starts accepting.
  static Future<SshTunnel> open(
    SSHClient client,
    int remotePort, {
    String remoteHost = '127.0.0.1',
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final tunnel = SshTunnel._(server, client, remoteHost, remotePort);
    server.listen(tunnel._accept, onError: (_) {}, cancelOnError: false);
    return tunnel;
  }

  @override
  int get localPort => _server.port;

  @override
  Uri uri({String scheme = 'https', String path = '/'}) =>
      Uri(scheme: scheme, host: '127.0.0.1', port: localPort, path: path);

  @override
  bool get isOpen => !_closed && !_client.isClosed;

  Future<void> _accept(Socket socket) async {
    socket.setOption(SocketOption.tcpNoDelay, true);
    final SSHForwardChannel channel;
    try {
      channel = await _client.forwardLocal(remoteHost, remotePort);
    } on Object {
      socket.destroy();
      return;
    }
    _channels.add(channel);
    unawaited(socket.cast<List<int>>().pipe(channel.sink).catchError((_) {}));
    unawaited(channel.stream.cast<List<int>>().pipe(socket).catchError((_) {}));
    unawaited(channel.done.whenComplete(() {
      _channels.remove(channel);
      socket.destroy();
    }));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close();
    for (final c in _channels.toList()) {
      await c.close();
    }
    _channels.clear();
  }
}
