import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/app_error.dart';
import 'security/app_log.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // No telemetry, no crash reporter: errors are scrubbed and, in release,
  // never printed anywhere.
  AppLog.installGlobalHandlers();
  registerFontLicenses();
  runApp(const ProviderScope(retry: noProviderRetry, child: MoavDeployApp()));
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
