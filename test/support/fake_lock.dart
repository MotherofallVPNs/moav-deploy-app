import 'dart:async';

import 'package:local_auth/local_auth.dart';
import 'package:moav_deploy/security/app_lock.dart';
import 'package:moav_deploy/security/onboarding.dart';

/// Each `authenticate()` call waits for the test to complete its gate, so a
/// test can assert what is on screen while the biometric prompt is up.
class GatedLock extends AppLockService {
  final gates = <Completer<bool>>[];

  /// The `disguised` flag of each call, in order.
  final reasons = <bool>[];

  /// The `biometricOnly` flag of each call, in order.
  final biometricOnly = <bool>[];

  /// What the device has enrolled; empty means passcode only.
  List<BiometricType> enrolled = const [];

  @override
  Future<bool> canLock() async => true;

  @override
  Future<List<BiometricType>> enrolledBiometrics() async => enrolled;

  @override
  Future<AuthOutcome> authenticate({
    bool disguised = false,
    bool biometricOnly = false,
  }) {
    reasons.add(disguised);
    this.biometricOnly.add(biometricOnly);
    final c = Completer<bool>();
    gates.add(c);
    return c.future
        .then((ok) => ok ? AuthOutcome.success : AuthOutcome.failed);
  }
}

/// Answers each prompt from [outcomes] at once and records how it was asked.
class ScriptedLock extends AppLockService {
  ScriptedLock({this.enrolled = const [BiometricType.face]});

  /// What the device has enrolled; change it between attempts at will.
  List<BiometricType> enrolled;

  /// Queue of answers; the last one repeats.
  final outcomes = <AuthOutcome>[AuthOutcome.failed];

  /// The `biometricOnly` flag of each prompt, in order.
  final prompts = <bool>[];

  @override
  Future<bool> canLock() async => true;

  @override
  Future<List<BiometricType>> enrolledBiometrics() async => enrolled;

  @override
  Future<AuthOutcome> authenticate({
    bool disguised = false,
    bool biometricOnly = false,
  }) async {
    prompts.add(biometricOnly);
    return outcomes.length == 1 ? outcomes.first : outcomes.removeAt(0);
  }
}

/// Onboarding already done, so tests land on the home screen.
class OnboardedStore implements OnboardingStore {
  @override
  Future<bool> isComplete() async => true;

  @override
  Future<void> markComplete() async {}
}
