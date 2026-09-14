import 'package:flutter/material.dart';

import 'features/servers/servers_home_screen.dart';
import 'security/app_lock.dart';

class MoavDeployApp extends StatelessWidget {
  const MoavDeployApp({super.key, this.lockEnabled = true});

  /// Set to false in tests to bypass the biometric gate.
  final bool lockEnabled;

  @override
  Widget build(BuildContext context) {
    const home = ServersHomeScreen();
    return MaterialApp(
      title: 'MoaV Deploy',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1E6FD9),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1E6FD9),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: lockEnabled ? const AppLockGate(child: home) : home,
    );
  }
}
