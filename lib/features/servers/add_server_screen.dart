import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add_server_form.dart';
import 'servers_provider.dart';

class AddServerScreen extends ConsumerWidget {
  const AddServerScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const AddServerScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = ref.watch(addServerFormProvider);
    final notifier = ref.read(addServerFormProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Add server')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Label (optional)',
              hintText: 'e.g. Frankfurt',
            ),
            textInputAction: TextInputAction.next,
            onChanged: notifier.setLabel,
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              labelText: 'Host',
              hintText: 'vpn.example.com or 203.0.113.7',
              errorText: form.host.isEmpty ? null : form.hostError,
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            onChanged: notifier.setHost,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: form.port,
                  decoration: InputDecoration(
                    labelText: 'Port',
                    errorText: form.portError,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: notifier.setPort,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: form.username,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    errorText: form.usernameError,
                  ),
                  autocorrect: false,
                  onChanged: notifier.setUsername,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Authentication', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<AuthChoice>(
            segments: const [
              ButtonSegment(
                value: AuthChoice.generateKey,
                label: Text('Generate key'),
                icon: Icon(Icons.vpn_key),
              ),
              ButtonSegment(
                value: AuthChoice.importKey,
                label: Text('Import key'),
                icon: Icon(Icons.file_upload),
              ),
              ButtonSegment(
                value: AuthChoice.password,
                label: Text('Password'),
                icon: Icon(Icons.password),
              ),
            ],
            selected: {form.authChoice},
            onSelectionChanged: (s) => notifier.setAuthChoice(s.first),
          ),
          const SizedBox(height: 16),
          _AuthSection(form: form, notifier: notifier),
          if (form.error != null) ...[
            const SizedBox(height: 16),
            Text(
              form.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: form.isValid && !form.submitting
                ? () => _submit(context, ref)
                : null,
            child: form.submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save server'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(addServerFormProvider.notifier);
    final keyError = notifier.importedKeyError();
    if (keyError != null) {
      notifier.setError(keyError);
      return;
    }
    final form = ref.read(addServerFormProvider);
    final secret = form.secret;
    if (secret == null) return;

    notifier.setSubmitting(true);
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    try {
      await ref.read(serversProvider.notifier).add(
            form.toProfile(id),
            secret: secret,
          );
    } on Object catch (e) {
      notifier.setError('Could not save: $e');
      return;
    }
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _AuthSection extends StatelessWidget {
  const _AuthSection({required this.form, required this.notifier});

  final AddServerFormState form;
  final AddServerFormNotifier notifier;

  @override
  Widget build(BuildContext context) {
    switch (form.authChoice) {
      case AuthChoice.generateKey:
        final key = form.generatedKey;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'An ed25519 key is generated on this device. The private key '
              'never leaves the secure store; you install the public key on '
              'the server.',
            ),
            const SizedBox(height: 12),
            if (key == null)
              OutlinedButton.icon(
                onPressed: notifier.generateKey,
                icon: const Icon(Icons.autorenew),
                label: const Text('Generate ed25519 key'),
              )
            else ...[
              const Text('Public key (install on server):'),
              const SizedBox(height: 4),
              SelectableText(
                key.publicKeyOpenSsh,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ],
        );
      case AuthChoice.importKey:
        return TextField(
          decoration: const InputDecoration(
            labelText: 'Private key (OpenSSH / PEM, ed25519)',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          maxLines: 6,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          onChanged: notifier.setImportedKey,
        );
      case AuthChoice.password:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: notifier.setPassword,
            ),
            const SizedBox(height: 8),
            Text(
              'Password auth is a fallback. Prefer a key so a seized device '
              'can be wiped without changing the server password.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
    }
  }
}
