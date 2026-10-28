import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'moav_controller.dart';

/// Zips the text configs the app already fetched. This is the fallback when
/// the box cannot build the archive itself (see
/// [MoavController.getBundleArchive]): QR images and the HTML guide are
/// never fetched, so they are not in this zip.
Uint8List encodeBundleZip(Bundle bundle) {
  final archive = Archive();
  for (final e in bundle.entries) {
    archive.add(ArchiveFile.string(e.fileName, e.content));
  }
  return ZipEncoder().encodeBytes(archive);
}

/// File name of the shared archive, whichever way it was built.
String bundleZipFileName(String user) => '$user-moav-bundle.zip';
