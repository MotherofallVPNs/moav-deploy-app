import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/servers/servers_home_screen.dart';
import 'security/app_lock.dart';
import 'security/decoy/decoy_gate.dart';
import 'security/decoy/decoy_provider.dart';
import 'security/onboarding.dart';
import 'theme/moav_theme.dart';

class MoavDeployApp extends ConsumerWidget {
  const MoavDeployApp({super.key, this.lockEnabled = true});

  /// Set to false in tests to bypass the biometric gate.
  final bool lockEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const home = ServersHomeScreen();
    final theme = moavDarkTheme();
    final disguised = ref.watch(decoyProvider.select((c) => c.enabled));
    final app = MaterialApp(
      // Also the task-switcher label on Android: never MoaV while disguised.
      title: disguised ? 'Notes' : 'MoaV Deploy',
      // Dark-first: the MoaV design system has one (dark) theme.
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      home: lockEnabled
          ? const FirstRunGate(child: AppLockGate(child: home))
          : home,
    );
    return DecoyGate(child: app);
  }
}
