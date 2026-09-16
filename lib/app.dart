import 'package:flutter/material.dart';

import 'features/servers/servers_home_screen.dart';
import 'security/app_lock.dart';
import 'theme/moav_theme.dart';

class MoavDeployApp extends StatelessWidget {
  const MoavDeployApp({super.key, this.lockEnabled = true});

  /// Set to false in tests to bypass the biometric gate.
  final bool lockEnabled;

  @override
  Widget build(BuildContext context) {
    const home = ServersHomeScreen();
    final theme = moavDarkTheme();
    return MaterialApp(
      title: 'MoaV Deploy',
      // Dark-first: the MoaV design system has one (dark) theme.
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      home: lockEnabled ? const AppLockGate(child: home) : home,
    );
  }
}
