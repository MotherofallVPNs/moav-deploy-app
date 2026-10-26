import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_log.dart';
import 'secure_cred_store.dart';

/// What the quick wipe removed. Nothing here is secret; it is shown to the
/// user as confirmation.
class WipeReport {
  const WipeReport({
    required this.storeEntries,
    required this.webDataCleared,
    required this.clipboardCleared,
  });

  /// Keys removed from the secure store (profiles, per-server secrets,
  /// SSH keys, install handles).
  final int storeEntries;

  /// Grafana cookies / cache / local storage were cleared.
  final bool webDataCleared;

  /// A copied share link or config was replaced with an empty clipboard.
  final bool clipboardCleared;
}

/// Device-seizure quick wipe, transport- and UI-agnostic.
///
/// Order matters: the secure store goes first because it is the only thing
/// that lets an attacker reach a server. Everything after it is best-effort
/// and never blocks the wipe from completing.
class WipeService {
  WipeService({
    required SecureCredStore store,
    Future<void> Function()? clearWebData,
    Future<void> Function()? clearClipboard,
  })  : _store = store,
        _clearWebData = clearWebData ?? defaultClearWebData,
        _clearClipboard = clearClipboard ?? defaultClearClipboard;

  final SecureCredStore _store;
  final Future<void> Function() _clearWebData;
  final Future<void> Function() _clearClipboard;

  Future<WipeReport> wipe() async {
    // 1. Secure store: keys, passwords, server list, install handles.
    //    Throws if anything survives; the caller shows that as an error.
    final removed = await _store.wipeAll();

    // 2. Grafana session cookies, cache and local storage.
    var web = false;
    try {
      await _clearWebData();
      web = true;
    } on Object catch (e) {
      AppLog.warn('wipe', 'web data not cleared: ${e.runtimeType}');
    }

    // 3. Clipboard, in case a share link or config was copied.
    var clip = false;
    try {
      await _clearClipboard();
      clip = true;
    } on Object catch (e) {
      AppLog.warn('wipe', 'clipboard not cleared: ${e.runtimeType}');
    }

    return WipeReport(
      storeEntries: removed,
      webDataCleared: web,
      clipboardCleared: clip,
    );
  }

  static Future<void> defaultClearWebData() async {
    await WebViewCookieManager().clearCookies();
    final c = WebViewController();
    await c.clearCache();
    await c.clearLocalStorage();
  }

  static Future<void> defaultClearClipboard() =>
      Clipboard.setData(const ClipboardData(text: ''));
}
