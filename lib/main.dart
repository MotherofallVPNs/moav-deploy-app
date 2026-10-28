import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/app_error.dart';
import 'security/app_log.dart';
import 'theme/moav_theme.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // No telemetry, no crash reporter: errors are scrubbed and, in release,
  // never printed anywhere.
  AppLog.installGlobalHandlers();
  registerFontLicenses();
  holdFirstFrameForMark(binding);
  runApp(const ProviderScope(retry: noProviderRetry, child: MoavDeployApp()));
}

/// Keeps the native splash up until the MoaV mark is decoded.
///
/// The first Flutter frame repeats the launch lockup ([MoavLockup]); without
/// this the mark would be missing from that frame while the PNG decodes, a
/// visible blink between the native splash and the app. Bundled fonts need
/// no such wait: the engine loads them synchronously on first use.
void holdFirstFrameForMark(WidgetsBinding binding) {
  binding.deferFirstFrame();
  final stream =
      const AssetImage(MoavMark.asset).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void release() {
    stream.removeListener(listener);
    binding.allowFirstFrame();
  }

  listener = ImageStreamListener(
    (_, _) => release(),
    onError: (_, _) => release(),
  );
  stream.addListener(listener);
}

/// Bundled font license texts, keyed by the package names shown on the
/// Flutter licenses page. The SIL Open Font License requires the license to
/// accompany the fonts wherever they are distributed.
const fontLicenseAssets = <String, String>{
  'Inter': 'assets/fonts/LICENSE-Inter.txt',
  'JetBrains Mono': 'assets/fonts/LICENSE-JetBrainsMono.txt',
};

/// Adds the bundled font licenses to [LicenseRegistry] so they appear in
/// `showLicensePage` next to the Dart and Flutter package licenses.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in fontLicenseAssets.entries) {
      final text = await rootBundle.loadString(entry.value);
      yield LicenseEntryWithLineBreaks([entry.key], text);
    }
  });
}
