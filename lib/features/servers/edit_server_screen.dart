import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/server_profile.dart';
import '../../core/ssh_endpoint.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/error_view.dart';
import 'servers_provider.dart';

class EditServerScreen extends ConsumerStatefulWidget {
  const EditServerScreen({super.key, required this.profile});

  final ServerProfile profile;

  static Route<void> route(ServerProfile profile) =>
      MaterialPageRoute(builder: (_) => EditServerScreen(profile: profile));

  @override
  ConsumerState<EditServerScreen> createState() => _EditServerScreenState();
}

class _EditServerScreenState extends ConsumerState<EditServerScreen> {
  late final TextEditingController _label;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _label = TextEditingController(text: p.label);
    _host = TextEditingController(text: p.host);
    _port = TextEditingController(text: '${p.port}');
    _username = TextEditingController(text: p.username);
  }

  @override
  void dispose() {
    _label.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MoavScaffold(
    appBar: AppBar(title: const Text('Edit server')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        TextField(
          controller: _label,
          decoration: const InputDecoration(labelText: 'Label'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _host,
          decoration: const InputDecoration(labelText: 'Host'),
          style: moavMono(size: 14),
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _port,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
                style: moavMono(size: 14),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'Username'),
                autocorrect: false,
                style: moavMono(size: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Your saved password or SSH key is kept unchanged.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          ErrorBanner(error: _error!),
        ],
        const SizedBox(height: 24),
        GradientButton(
          onPressed: _saving ? null : _save,
          busy: _saving,
          expand: true,
          icon: Icons.save_outlined,
          label: 'Save changes',
        ),
      ],
    ),
  );

  Future<void> _save() async {
    final endpoint = SshEndpoint.tryParse(_host.text);
    final username = _username.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (endpoint == null) {
      setState(() => _error = 'Enter a hostname or IP address, without spaces');
      return;
    }
    final host = endpoint.host;
    if (username.isEmpty || port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Enter a username and a port from 1 to 65535');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(serversProvider.notifier)
          .updateProfile(
            widget.profile.copyWith(
              label: _label.text.trim().isEmpty ? host : _label.text.trim(),
              host: host,
              port: port,
              username: username,
            ),
          );
      if (mounted) {
        Navigator.pop(context);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorSummary(e);
        });
      }
    }
  }
}
