import 'package:flutter/services.dart';
import 'package:moav_deploy/security/decoy/decoy_identity.dart';

/// Records launcher identity switches instead of touching the platform.
class FakeDecoyIdentity implements DecoyIdentity {
  FakeDecoyIdentity({this.renameLauncher = true, this.switchIcon = true});

  final bool renameLauncher;
  final bool switchIcon;

  /// Every `apply` call, true for Notes.
  final applied = <bool>[];

  /// When set, `apply` throws like a failing platform call would.
  bool fail = false;
  bool closed = false;

  @override
  Future<DecoyCapabilities> capabilities() async => DecoyCapabilities(
        renameLauncher: renameLauncher,
        switchIcon: switchIcon,
      );

  @override
  Future<bool> isNotes() async => applied.isNotEmpty && applied.last;

  @override
  Future<void> apply({required bool notes}) async {
    if (fail) throw PlatformException(code: 'decoy', message: 'nope');
    applied.add(notes);
  }

  @override
  Future<bool> closeApp() async {
    closed = true;
    return renameLauncher;
  }
}
