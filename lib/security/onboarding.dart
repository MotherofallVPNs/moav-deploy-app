import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../theme/moav_theme.dart';

/// Remembers whether the first-run screen has been shown. Lives in the same
/// secure store as everything else so a wipe also resets it.
class OnboardingStore {
  OnboardingStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _key = 'moav.onboarding_complete.v1';

  Future<bool> isComplete() async {
    try {
      return await _storage.read(key: _key) == 'true';
    } on Object catch (_) {
      return false;
    }
  }

  Future<void> markComplete() => _storage.write(key: _key, value: 'true');
}

final onboardingStoreProvider =
    Provider<OnboardingStore>((_) => OnboardingStore());

class OnboardingNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.read(onboardingStoreProvider).isComplete();

  Future<void> complete() async {
    await ref.read(onboardingStoreProvider).markComplete();
    state = const AsyncData(true);
  }
}

final onboardingProvider =
    AsyncNotifierProvider<OnboardingNotifier, bool>(OnboardingNotifier.new);

/// Shows [OnboardingScreen] once, before the lock gate ever prompts. After
/// the flag is set the child (normally [AppLockGate]) is built directly.
class FirstRunGate extends ConsumerWidget {
  const FirstRunGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = ref.watch(onboardingProvider);
    return switch (done) {
      AsyncData(value: true) => child,
      AsyncData(value: false) || AsyncError() => OnboardingScreen(
          onContinue: () => ref.read(onboardingProvider.notifier).complete(),
        ),
      // While the flag loads, repeat the native launch lockup in the same
      // place so the first frame does not blank out or shift the mark.
      _ => const MoavScaffold(body: Center(child: MoavLockup())),
    };
  }
}

/// One-screen welcome that frames the app lock as protection, not a wall.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MoavScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: MoavLockup()),
                  const SizedBox(height: 20),
                  Text(
                    'Your servers, in your pocket. Safely.',
                    textAlign: TextAlign.center,
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'MoaV Deploy keeps SSH keys and server credentials on this '
                    'phone only. App lock makes sure only you can open them.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium
                        ?.copyWith(color: MoavColors.textSecondary),
                  ),
                  const SizedBox(height: 28),
                  const _Point(
                    icon: Icons.fingerprint,
                    title: 'Unlock with what you already use',
                    body: 'Fingerprint, face or your device passcode. '
                        'Nothing new to remember.',
                  ),
                  const _Point(
                    icon: Icons.phonelink_lock_outlined,
                    title: 'Locks whenever you step away',
                    body: 'Every launch and every return from the background.',
                  ),
                  const _Point(
                    icon: Icons.delete_forever_outlined,
                    title: 'Emergency wipe stays one tap away',
                    body: 'Reachable from the lock screen, no unlock needed.',
                  ),
                  const SizedBox(height: 32),
                  GradientButton(
                    onPressed: onContinue,
                    icon: Icons.lock_outline,
                    label: 'Turn on app lock',
                    expand: true,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'On phones without a screen lock the app opens directly.',
                    textAlign: TextAlign.center,
                    style:
                        text.bodySmall?.copyWith(color: MoavColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.bodySmall
                      ?.copyWith(color: MoavColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
