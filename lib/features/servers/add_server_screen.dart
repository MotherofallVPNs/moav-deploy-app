import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/moav_theme.dart';
import '../../widgets/error_view.dart';
import '../keys/keyring_provider.dart';
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

    return MoavScaffold(
      appBar: AppBar(title: const Text('Add server')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SectionHeader(
            'Connection',
            padding: EdgeInsets.only(top: 4, bottom: 10),
          ),
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
            style: moavMono(size: 14),
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
                  style: moavMono(size: 14),
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
                  style: moavMono(size: 14),
                  autocorrect: false,
                  onChanged: notifier.setUsername,
                ),
              ),
            ],
          ),
          const SectionHeader('Authentication'),
          SegmentedButton<AuthChoice>(
            segments: const [
              ButtonSegment(
                value: AuthChoice.savedKey,
                label: Text('Saved'),
                icon: Icon(Icons.key_outlined),
              ),
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
          const SizedBox(height: 12),
          MoavCard(
            accent: form.authChoice == AuthChoice.generateKey,
            child: _AuthSection(form: form, notifier: notifier),
          ),
          if (form.error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(error: form.error!),
          ],
          if (form.notice != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  size: 18,
                  color: MoavColors.pass,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    form.notice!,
                    style: const TextStyle(color: MoavColors.pass),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          GradientButton(
            onPressed: form.isValid && !form.submitting
                ? () => _submit(context, ref)
                : null,
            busy: form.submitting,
            expand: true,
            icon: Icons.save_outlined,
            label: 'Save server',
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
      if (form.authChoice == AuthChoice.generateKey ||
          form.authChoice == AuthChoice.importKey) {
        await ref
            .read(keyringProvider.notifier)
            .add(
              label: form.label.trim().isEmpty
                  ? 'MoaV device key'
                  : '${form.label.trim()} key',
              privateKeyPem: secret,
            );
      }
      await ref
          .read(serversProvider.notifier)
          .add(form.toProfile(id), secret: secret);
    } on Object catch (e) {
      notifier.setError('Could not save: ${errorSummary(e)}');
      return;
    }
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _AuthSection extends ConsumerWidget {
  const _AuthSection({required this.form, required this.notifier});

  final AddServerFormState form;
  final AddServerFormNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    switch (form.authChoice) {
      case AuthChoice.savedKey:
        final keys = ref.watch(keyringProvider);
        return keys.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              Text('Could not load saved keys: ${errorSummary(e)}'),
          data: (items) => items.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('No reusable keys yet.'),
                    const SizedBox(height: 8),
                    Text(
                      'Generate or import a key once and it will appear here for every server.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                )
              : DropdownButtonFormField<String>(
                  initialValue: form.savedKey?.id,
                  decoration: const InputDecoration(labelText: 'Device key'),
                  items: [
                    for (final key in items)
                      DropdownMenuItem(value: key.id, child: Text(key.label)),
                  ],
                  onChanged: (id) {
                    if (id == null) return;
                    notifier.selectSavedKey(
                      items.firstWhere((k) => k.id == id),
                    );
                  },
                ),
        );
      case AuthChoice.generateKey:
        final key = form.generatedKey;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBadge(Icons.key, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'On-device ed25519 key',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (key != null)
                  const StatusPill(
                    'generated',
                    tone: StatusTone.pass,
                    dot: false,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'The key pair is generated on this phone. The private key never '
              'leaves the secure store; only the public key goes on the server.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            if (key == null)
              GradientButton(
                onPressed: notifier.generateKey,
                icon: Icons.autorenew,
                label: 'Generate ed25519 key',
              )
            else ...[
              Text('PUBLIC KEY', style: moavLabel(size: 10)),
              const SizedBox(height: 6),
              CodeBlock(key.publicKeyOpenSsh, size: 11.5),
              const SizedBox(height: 6),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: key.publicKeyOpenSsh),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Public key copied')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                  TextButton.icon(
                    onPressed: notifier.generateKey,
                    icon: const Icon(Icons.autorenew, size: 16),
                    label: const Text('Regenerate'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (form.keyInstalled)
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: MoavColors.pass),
                    SizedBox(width: 8),
                    Expanded(child: Text('Installed on the server')),
                  ],
                )
              else ...[
                Text(
                  'Install it on the server now (uses the server password '
                  'once, never stored), or add the line above to '
                  '~/.ssh/authorized_keys yourself.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Server password (one-time)',
                  ),
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: notifier.setOneTimePassword,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: form.canInstallKey
                      ? notifier.installKeyOnServer
                      : null,
                  icon: form.installingKey
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Install key on server'),
                ),
              ],
            ],
          ],
        );
      case AuthChoice.importKey:
        return TextField(
          decoration: const InputDecoration(
            labelText: 'Private key (OpenSSH / PEM, ed25519)',
            alignLabelWithHint: true,
          ),
          maxLines: 6,
          autocorrect: false,
          enableSuggestions: false,
          style: moavMono(size: 12, weight: FontWeight.w400),
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
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
    }
  }
}
