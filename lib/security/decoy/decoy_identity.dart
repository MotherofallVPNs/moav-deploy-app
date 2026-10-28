import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the platform can change about the installed app's identity.
class DecoyCapabilities {
  const DecoyCapabilities({
    required this.renameLauncher,
    required this.switchIcon,
  });

  static const none = DecoyCapabilities(
    renameLauncher: false,
    switchIcon: false,
  );

  /// Android: the launcher label becomes "Notes". iOS cannot do this.
  final bool renameLauncher;

  /// The launcher icon becomes the Notes icon.
  final bool switchIcon;
}

/// Switches the launcher identity (name and icon) on the native side.
///
/// Android flips the two predeclared `activity-alias` components; iOS sets
/// the alternate app icon. See `docs/DISGUISE.md` for what each platform
/// can and cannot hide.
abstract class DecoyIdentity {
  Future<DecoyCapabilities> capabilities();

  /// True when the launcher currently shows the Notes identity.
  Future<bool> isNotes();

  /// Makes the launcher show Notes ([notes] true) or MoaV Deploy. Idempotent.
  Future<void> apply({required bool notes});

  /// Finishes the current task so the next launch uses the new identity.
  /// Returns false where the platform offers no such thing (iOS).
  Future<bool> closeApp();

  /// The platform implementation, or a no-op off Android and iOS.
  static DecoyIdentity forPlatform() => switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS =>
          const MethodChannelDecoyIdentity(),
        _ => const UnsupportedDecoyIdentity(),
      };
}

class MethodChannelDecoyIdentity implements DecoyIdentity {
  const MethodChannelDecoyIdentity();

  static const channel = MethodChannel('org.motherofallvpns.moavdeploy/decoy');

  @override
  Future<DecoyCapabilities> capabilities() async {
    final map = await channel.invokeMapMethod<String, Object?>('capabilities');
    return DecoyCapabilities(
      renameLauncher: map?['renameLauncher'] == true,
      switchIcon: map?['switchIcon'] == true,
    );
  }

  @override
  Future<bool> isNotes() async =>
      await channel.invokeMethod<String>('getIdentity') == 'notes';

  @override
  Future<void> apply({required bool notes}) =>
      channel.invokeMethod<void>('setIdentity', {'notes': notes});

  @override
  Future<bool> closeApp() async =>
      await channel.invokeMethod<bool>('closeApp') ?? false;
}

/// Desktop, web and tests: the in-app decoy still works, the launcher
/// identity does not change.
class UnsupportedDecoyIdentity implements DecoyIdentity {
  const UnsupportedDecoyIdentity();

  @override
  Future<DecoyCapabilities> capabilities() async => DecoyCapabilities.none;

  @override
  Future<bool> isNotes() async => false;

  @override
  Future<void> apply({required bool notes}) async {}

  @override
  Future<bool> closeApp() async => false;
}

final decoyIdentityProvider =
    Provider<DecoyIdentity>((_) => DecoyIdentity.forPlatform());
