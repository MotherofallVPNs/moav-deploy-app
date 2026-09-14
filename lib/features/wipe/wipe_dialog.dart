import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/error_view.dart';
import 'wipe_provider.dart';

/// Confirms and runs the device-seizure quick wipe.
///
/// Returns true when the wipe ran. Callers decide what to do with the
/// navigation stack; this only shows the confirmation and the outcome.
Future<bool> showWipeDialog(BuildContext context, WidgetRef ref, {int? serverCount}) async {
  final what = serverCount == null
      ? 'every saved server'
      : serverCount == 1
          ? '1 saved server'
          : '$serverCount saved servers';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.delete_forever, color: Theme.of(ctx).colorScheme.error),
      title: const Text('Wipe this device?'),
      content: Text(
        'Removes $what, all SSH keys and passwords, pending install handles, '
        'Grafana web data and the clipboard from this phone.\n\n'
        'The servers themselves are not touched. To manage them again you '
        'will need to add them with a new key.\n\n'
        'This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Wipe everything'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  final messenger = ScaffoldMessenger.maybeOf(context);
  final report = await ref.read(wipeProvider.notifier).wipe();
  if (!context.mounted) return true;
  if (report == null) {
    final err = ref.read(wipeProvider).error;
    messenger?.showSnackBar(SnackBar(
      content: Text('Wipe incomplete: ${errorSummary(err ?? 'unknown error')}'),
      duration: const Duration(seconds: 8),
    ));
  } else {
    messenger?.showSnackBar(SnackBar(
      content: Text(
        'Wiped. ${report.storeEntries} secure-store item(s) removed'
        '${report.webDataCleared ? ', web data cleared' : ''}'
        '${report.clipboardCleared ? ', clipboard cleared' : ''}.',
      ),
      duration: const Duration(seconds: 6),
    ));
  }
  return true;
}
