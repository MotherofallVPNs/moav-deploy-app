import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/moav_theme.dart';
import '../../widgets/moav_app_bar.dart';
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
      appBar: MoavAppBar(title: const Text('Add server')),
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
          _AuthChoiceGrid(
            selected: form.authChoice,
            onChanged: notifier.setAuthChoice,
          ),
          const SizedBox(height: 12),
          MoavCard(
            accent: form.authChoice != AuthChoice.password,
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
      final keyring = ref.read(keyringProvider.notifier);
      if (form.authChoice == AuthChoice.importKey) {
        await keyring.add(
          label: AddServerFormNotifier.generatedKeyLabel(form.label),
          privateKeyPem: secret,
        );
      } else if (form.authChoice == AuthChoice.generateKey) {
        // Saved at generation time; only the label can have changed since.
        final id = form.generatedKeyId;
        if (id != null && form.label.trim().isNotEmpty) {
          await keyring.rename(
            id,
            AddServerFormNotifier.generatedKeyLabel(form.label),
          );
        }
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
          data: (items) {
            if (items.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No reusable keys yet.'),
                  const SizedBox(height: 8),
                  Text(
                    'Generate or import a key once and it will appear here for every server.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () =>
                        notifier.setAuthChoice(AuthChoice.generateKey),
                    icon: const Icon(Icons.autorenew, size: 16),
                    label: const Text('Generate a key instead'),
                  ),
                ],
              );
            }
            // Most connects reuse one device key: preselect the newest.
            if (form.savedKey == null) {
              final newest = items.reduce(
                (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
              );
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => notifier.selectSavedKey(newest),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
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
                if (form.savedKey != null) ...[
                  const SizedBox(height: 10),
                  Text('PUBLIC KEY', style: moavLabel(size: 10)),
                  const SizedBox(height: 6),
                  CodeBlock(form.savedKey!.publicKey, size: 11.5),
                  const SizedBox(height: 6),
                  Text(
                    'Make sure this line is in ~/.ssh/authorized_keys on the server.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            );
          },
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

/// One card per credential type: icon, label, one-line hint. A 2x2 grid
/// keeps every label on a single line at phone widths.
class _AuthChoiceGrid extends StatelessWidget {
  const _AuthChoiceGrid({required this.selected, required this.onChanged});

  final AuthChoice selected;
  final ValueChanged<AuthChoice> onChanged;

  static const _options = [
    (
      AuthChoice.savedKey,
      Icons.key_outlined,
      'Saved key',
      'Reuse a key from this phone',
    ),
    (
      AuthChoice.generateKey,
      Icons.autorenew,
      'Generate key',
      'New ed25519 key, made on-device',
    ),
    (
      AuthChoice.importKey,
      Icons.file_upload_outlined,
      'Import key',
      'Paste an existing private key',
    ),
    (
      AuthChoice.password,
      Icons.password,
      'Password',
      'Fallback when no key is possible',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    Widget tile((AuthChoice, IconData, String, String) o) => _AuthChoiceCard(
      icon: o.$2,
      label: o.$3,
      hint: o.$4,
      selected: o.$1 == selected,
      onTap: () => onChanged(o.$1),
    );
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: tile(_options[0])),
            const SizedBox(width: 10),
            Expanded(child: tile(_options[1])),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: tile(_options[2])),
            const SizedBox(width: 10),
            Expanded(child: tile(_options[3])),
          ],
        ),
      ],
    );
  }
}

class _AuthChoiceCard extends StatelessWidget {
  const _AuthChoiceCard({
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? MoavColors.cyan : MoavColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected
              ? MoavColors.cyan.withValues(alpha: 0.08)
              : MoavColors.card,
          borderRadius: MoavRadius.control,
          border: Border.all(
            color: selected
                ? MoavColors.cyan.withValues(alpha: 0.6)
                : MoavColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: MoavRadius.control,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: accent),
                      const Spacer(),
                      Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: accent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? MoavColors.text
                          : MoavColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MoavColors.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
