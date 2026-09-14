import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'security/app_log.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // No telemetry, no crash reporter: errors are scrubbed and, in release,
  // never printed anywhere.
  AppLog.installGlobalHandlers();
  runApp(const ProviderScope(child: MoavDeployApp()));
}
