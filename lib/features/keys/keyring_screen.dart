import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../security/key_export_service.dart';
import '../../security/key_service.dart';
import '../../security/secure_cred_store.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/error_view.dart';
import 'keyring_provider.dart';

class KeyringScreen extends ConsumerWidget {
  const KeyringScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const KeyringScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(keyringProvider);
    return MoavScaffold(
      appBar: AppBar(
        title: const Text('SSH keys'),
        actions: [
          IconButton(
            tooltip: 'Import encrypted key',
            onPressed: () => _import(context, ref),
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: 'Generate key',
            onPressed: () => _generate(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: keys.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(keyringProvider)),
        data: (items) => items.isEmpty
            ? const EmptyState(
                icon: Icons.key_outlined,
                title: 'No device keys yet',
                body:
                    'Generate or import a key once, then reuse it when adding servers.',
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _KeyCard(keyData: items[i]),
              ),
      ),
    );
  }

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    final label = await _ask(context, 'New key', 'Label', secret: false);
    if (label == null) return;
    final material = await const KeyService().generateEd25519(
      comment: label.isEmpty ? 'moav-deploy' : label,
    );
    await ref
        .read(keyringProvider.notifier)
        .add(
          label: label.isEmpty ? 'Device key' : label,
          privateKeyPem: material.privateKeyPem,
        );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final bundle = TextEditingController();
    final passphrase = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import encrypted key'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bundle,
                minLines: 3,
                maxLines: 6,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Encrypted export',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passphrase,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Passphrase'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final decoded = await const KeyExportService().decrypt(
        bundle.text,
        passphrase.text,
      );
      final error = const KeyService().validatePrivateKeyPem(
        decoded.privateKeyPem,
      );
      if (error != null) throw FormatException(error);
      await ref
          .read(keyringProvider.notifier)
          .add(label: decoded.label, privateKeyPem: decoded.privateKeyPem);
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorSummary(e))));
      }
    } finally {
      bundle.dispose();
      passphrase.dispose();
    }
  }
}

class _KeyCard extends ConsumerWidget {
  const _KeyCard({required this.keyData});
  final StoredSshKey keyData;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MoavCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const IconBadge(Icons.key_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                keyData.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'rename') _rename(context, ref);
                if (value == 'export') _export(context, ref);
                if (value == 'delete') _delete(context, ref);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'export', child: Text('Encrypted export')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete from keyring'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        CodeBlock(keyData.publicKey, size: 10.5),
        TextButton.icon(
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: keyData.publicKey)),
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy public key'),
        ),
      ],
    ),
  );

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final label = await _ask(
      context,
      'Rename key',
      'Label',
      initial: keyData.label,
      secret: false,
    );
    if (label != null && label.trim().isNotEmpty) {
      await ref.read(keyringProvider.notifier).rename(keyData.id, label);
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final passphrase = await _ask(
      context,
      'Encrypted export',
      'Passphrase (10+ characters)',
      secret: true,
    );
    if (passphrase == null) return;
    try {
      final pem = await ref.read(keyringProvider.notifier).secret(keyData.id);
      if (pem == null) throw StateError('Private key is missing');
      final bundle = await const KeyExportService().encrypt(
        label: keyData.label,
        privateKeyPem: pem,
        passphrase: passphrase,
      );
      await SharePlus.instance.share(
        ShareParams(
          text: bundle,
          subject: 'Encrypted MoaV SSH key: ${keyData.label}',
        ),
      );
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorSummary(e))));
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete key from keyring?'),
        content: const Text(
          'Servers already using this key keep their saved copy. This only removes it from the reusable key list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(keyringProvider.notifier).remove(keyData.id);
  }
}

Future<String?> _ask(
  BuildContext context,
  String title,
  String label, {
  String initial = '',
  required bool secret,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: secret,
        autocorrect: !secret,
        enableSuggestions: !secret,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
