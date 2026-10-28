import 'dart:async';

import 'package:moav_deploy/security/app_lock.dart';
import 'package:moav_deploy/security/onboarding.dart';

/// Each `authenticate()` call waits for the test to complete its gate, so a
/// test can assert what is on screen while the biometric prompt is up.
class GatedLock extends AppLockService {
  final gates = <Completer<bool>>[];

  /// The `disguised` flag of each call, in order.
  final reasons = <bool>[];

  @override
  Future<bool> canLock() async => true;

  @override
  Future<bool> authenticate({bool disguised = false}) {
    reasons.add(disguised);
    final c = Completer<bool>();
    gates.add(c);
    return c.future;
  }
}

/// Onboarding already done, so tests land on the home screen.
class OnboardedStore implements OnboardingStore {
  @override
  Future<bool> isComplete() async => true;

  @override
  Future<void> markComplete() async {}
}
