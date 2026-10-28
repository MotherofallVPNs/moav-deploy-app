import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../security/decoy/decoy_config.dart';
import '../../security/decoy/decoy_identity.dart';
import '../../security/decoy/decoy_pin.dart';
import '../../security/decoy/decoy_provider.dart';
import '../../theme/moav_theme.dart';
import '../../widgets/error_view.dart';
import '../../widgets/moav_app_bar.dart';

/// What this device can change, asked once from the native side.
final decoyCapabilitiesProvider = FutureProvider<DecoyCapabilities>(
  (ref) => ref.read(decoyIdentityProvider).capabilities(),
);

/// Turns disguise mode on and off. Reached from the home menu, i.e. only
/// after the app lock.
class DisguiseScreen extends ConsumerStatefulWidget {
  const DisguiseScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const DisguiseScreen());

  @override
  ConsumerState<DisguiseScreen> createState() => _DisguiseScreenState();
}

class _DisguiseScreenState extends ConsumerState<DisguiseScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  DecoyGesture _gesture = DecoyGesture.longPressTitle;
  bool _busy = false;
  String? _pinError;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _enable() async {
    final pin = _pin.text;
    if (!DecoyPin.isValid(pin)) {
      setState(() => _pinError =
          'Use ${DecoyPin.minLength} to ${DecoyPin.maxLength} digits');
      return;
    }
    if (pin != _confirm.text) {
      setState(() => _pinError = 'The two passcodes do not match');
      return;
    }
    setState(() {
      _pinError = null;
      _busy = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(decoyProvider.notifier)
          .enable(pin: pin, gesture: _gesture);
      _pin.clear();
      _confirm.clear();
    } on Object catch (e) {
      showErrorSnackBar(messenger, e, prefix: 'Disguise not turned on.');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _showSwitched(on: true);
  }

  Future<void> _disable() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off disguise?'),
        content: const Text(
          'The launcher goes back to MoaV Deploy and the passcode is '
          'forgotten. Your decoy notes stay on the device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(decoyProvider.notifier).disable();
    } on Object catch (e) {
      showErrorSnackBar(messenger, e, prefix: 'Disguise not turned off.');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _showSwitched(on: false);
  }

  /// Explains what just changed and, on Android, offers to close the task
  /// so the next launch carries the new name and icon everywhere.
  Future<void> _showSwitched({required bool on}) async {
    final caps = ref.read(decoyCapabilitiesProvider).value ??
        DecoyCapabilities.none;
    final identity = ref.read(decoyIdentityProvider);
    final body = on
        ? switch (caps) {
            DecoyCapabilities(renameLauncher: true) =>
              'The launcher now shows Notes. Close the app so the old entry '
                  'leaves the recent apps list, then open Notes from your '
                  'launcher.\n\n${_gesture.label}, then enter your passcode '
                  'to get back here.',
            DecoyCapabilities(switchIcon: true) =>
              'The home screen icon is now the Notes icon. iOS keeps the '
                  'name MoaV Deploy under it and on the launch screen.\n\n'
                  '${_gesture.label}, then enter your passcode to get back '
                  'here.',
            _ => 'This device cannot change the launcher name or icon, so '
                'only the Notes front screen is used.\n\n${_gesture.label}, '
                'then enter your passcode to get back here.',
          }
        : caps.renameLauncher
            ? 'The launcher shows MoaV Deploy again. Close the app so the '
                'Notes entry leaves the recent apps list.'
            : 'The app icon is MoaV Deploy again.';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(on ? 'Disguise is on' : 'Disguise is off'),
        content: Text(body),
        actions: [
          if (caps.renameLauncher)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Later'),
            ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (caps.renameLauncher) await identity.closeApp();
            },
            child: Text(caps.renameLauncher ? 'Close app' : 'Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(decoyProvider);
    final caps = ref.watch(decoyCapabilitiesProvider).value ??
        DecoyCapabilities.none;
    final text = Theme.of(context).textTheme;
    return MoavScaffold(
      appBar: const MoavAppBar(title: Text('Disguise mode')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          MoavCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconBadge(Icons.visibility_off_outlined, gradient: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Look like a Notes app', style: text.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'For when someone else may see or take this phone. '
                        'The app opens as a small, working notes app and '
                        'nothing about MoaV is on screen until you perform '
                        'the secret unlock.',
                        style: text.bodySmall
                            ?.copyWith(color: MoavColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader('What changes'),
          _Point(
            icon: Icons.apps_outlined,
            title: 'Launcher name and icon',
            body: switch (caps) {
              DecoyCapabilities(renameLauncher: true) =>
                'Your launcher shows Notes with a notes icon instead of '
                    'MoaV Deploy.',
              DecoyCapabilities(switchIcon: true) =>
                'The icon becomes the Notes icon. iOS does not let an app '
                    'change its name, so the label under the icon and the '
                    'launch screen still say MoaV Deploy.',
              _ => 'Not available on this device: only the Notes front '
                  'screen is used.',
            },
          ),
          const _Point(
            icon: Icons.sticky_note_2_outlined,
            title: 'A real notes screen',
            body: 'You can write and keep notes in it. They are stored '
                'separately from everything MoaV.',
          ),
          const _Point(
            icon: Icons.lock_open_outlined,
            title: 'Secret unlock',
            body: 'Perform the gesture you choose below on the Notes title, '
                'then enter your disguise passcode. The usual app lock '
                'follows, so MoaV stays protected.',
          ),
          const _Point(
            icon: Icons.delete_forever_outlined,
            title: 'Emergency wipe stays reachable',
            body: 'Secret unlock, then Emergency wipe on the lock screen. '
                'A wipe keeps the disguise on.',
          ),
          const SectionHeader('What stays visible'),
          _Point(
            icon: Icons.info_outline,
            title: 'The app settings page',
            body: caps.renameLauncher
                ? 'Settings > Apps still lists MoaV Deploy with its package '
                    'name, and so does the app store you installed from.'
                : 'Settings and the App Store still show MoaV Deploy.',
          ),
          if (config.enabled) ...[
            const SectionHeader('Status'),
            MoavCard(
              accent: true,
              child: Row(
                children: [
                  const IconBadge(Icons.check_circle_outline,
                      color: MoavColors.pass),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Disguise is on', style: text.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Secret unlock: ${config.gesture.label.toLowerCase()}, '
                          'then your passcode.',
                          style: text.bodySmall
                              ?.copyWith(color: MoavColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            GradientButton(
              onPressed: _busy ? null : _disable,
              busy: _busy,
              icon: Icons.visibility_outlined,
              label: 'Turn off disguise',
              expand: true,
            ),
          ] else ...[
            const SectionHeader('Set up'),
            Text(
              'Choose a passcode for this phone only. There is no recovery: '
              'if you forget it, reinstall the app and set MoaV up again.',
              style:
                  text.bodySmall?.copyWith(color: MoavColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: DecoyPin.maxLength,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: 'Disguise passcode',
                helperText:
                    '${DecoyPin.minLength} to ${DecoyPin.maxLength} digits',
                counterText: '',
                errorText: _pinError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: DecoyPin.maxLength,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Repeat passcode',
                counterText: '',
              ),
            ),
            const SizedBox(height: 18),
            Text('Secret gesture', style: text.titleSmall),
            RadioGroup<DecoyGesture>(
              groupValue: _gesture,
              onChanged: (g) {
                if (!_busy && g != null) setState(() => _gesture = g);
              },
              child: Column(
                children: [
                  for (final g in DecoyGesture.values)
                    RadioListTile<DecoyGesture>(
                      value: g,
                      title: Text(g.label),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GradientButton(
              onPressed: _busy ? null : _enable,
              busy: _busy,
              icon: Icons.visibility_off_outlined,
              label: 'Turn on disguise',
              expand: true,
            ),
          ],
        ],
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
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon, size: 36),
          const SizedBox(width: 12),
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
