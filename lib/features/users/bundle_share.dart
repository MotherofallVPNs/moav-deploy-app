import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/bundle_zip.dart';
import '../../core/moav_controller.dart';
import '../../widgets/error_view.dart';
import '../servers/servers_provider.dart';

/// Hands a zip to the platform share sheet. The bytes go to a temp file only
/// for as long as the sheet is open; it is removed once the sheet closes.
class BundleZipSharer {
  const BundleZipSharer();

  Future<void> share(
    String fileName,
    Uint8List bytes, {
    required String user,
    Rect? origin,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/zip', name: fileName)],
          subject: 'MoaV bundle ($user)',
          sharePositionOrigin: origin,
        ),
      );
    } finally {
      if (await file.exists()) await file.delete();
    }
  }
}

/// Overridden in widget tests to capture what would have been shared.
final bundleZipSharerProvider =
    Provider<BundleZipSharer>((_) => const BundleZipSharer());

/// Shares [bundle] as one `.zip`: the whole server-side directory when the
/// box can zip it, otherwise the fetched configs zipped on the phone.
/// [context] should be the button's own, so the iPad popover anchors to it.
Future<void> shareBundleZip(
  BuildContext context,
  WidgetRef ref, {
  required String serverId,
  required Bundle bundle,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize
      ? null
      : box.localToGlobal(Offset.zero) & box.size;
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Preparing the bundle zip…'),
      duration: Duration(seconds: 60),
    ),
  );
  Uint8List? bytes;
  try {
    bytes = await ref
        .read(moavControllerProvider(serverId))
        .getBundleArchive(bundle.user);
  } catch (_) {
    bytes = null;
  }
  messenger.hideCurrentSnackBar();
  if (bytes == null) {
    bytes = encodeBundleZip(bundle);
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Zipped the fetched configs; the server could not build the full '
          'archive with QR images and the guide.',
        ),
      ),
    );
  }
  try {
    await ref.read(bundleZipSharerProvider).share(
          bundleZipFileName(bundle.user),
          bytes,
          user: bundle.user,
          origin: origin,
        );
  } catch (e) {
    showErrorSnackBar(messenger, e, prefix: 'Could not share the zip.');
  }
}
