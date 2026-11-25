import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens this app's own page in the system Settings app.
///
/// On iOS that page holds the per-app Face ID switch: while it is off the
/// system reports no biometrics to the app, so the app lock falls back to
/// the passcode. On Android it is the "App info" page (permissions,
/// notifications).
class AppSettingsLink {
  const AppSettingsLink({
    MethodChannel channel = const MethodChannel(channelName),
    Future<bool> Function(Uri url)? launch,
  })  : _channel = channel,
        _launch = launch;

  // Mirrored in android/.../MainActivity.kt.
  static const channelName = 'org.motherofallvpns.moavdeploy/settings';
  static const method = 'openAppSettings';

  /// `UIApplication.openSettingsURLString`: this app's page in iOS Settings.
  static final iosUrl = Uri.parse('app-settings:');

  final MethodChannel _channel;
  final Future<bool> Function(Uri url)? _launch;

  /// Whether the running platform has a per-app settings page to open.
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// True when the Settings page was opened; false when the platform has
  /// none or the system refused.
  Future<bool> open() async {
    if (!supported) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final launch = _launch ?? _launchExternal;
        return await launch(iosUrl);
      }
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> _launchExternal(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}

final appSettingsLinkProvider =
    Provider<AppSettingsLink>((_) => const AppSettingsLink());
