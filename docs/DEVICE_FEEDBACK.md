# Device feedback

Findings from testing release builds on real phones. Each batch is dated and
lists the items as reported, followed by the outcome once addressed.

## 2026-10-26: Android, v0.2.0

1. **Biometric prompt icon.** The native authentication prompt (BiometricPrompt
   via local_auth) still shows the Flutter default logo, not the MoaV icon. The
   launcher icon was wired in the last release but the auth prompt still falls
   back. Verify every mipmap and drawable density is the MoaV icon, rebuild, and
   brand the prompt itself where local_auth allows it.
   Outcome: all 15 launcher resources in the repo are the MoaV mark (verified
   visually and by extracting them from a fresh APK). The prompt now carries a
   MoaV title and hint on Android and a MoaV cancel label on iOS. No Flutter
   artwork remains in the app; a stale icon on a phone that upgraded from
   v0.1.0 is launcher or system cache and clears on reinstall.

2. **Connection-failure errors.** When an SSH connection fails, surface a
   subtle, clear error in the UI (not a crash, not silence) that states the
   cause: host not found, connection refused, auth rejected, timeout.
   Outcome: a shared connection notice (icon by failure kind, one sentence,
   one hint) replaces plain-text snackbars; the server hub screen has an
   inline "Check connection" row; inline banners use the warn tone for
   retryable failures and red only for auth and credential problems.

3. **Connect to existing server fails with "Could not find bitchat.center:22".**
   Flow: existing server, on-device key, public key added to authorized_keys,
   connection fails at hostname resolution.
   Outcome: root cause is the release manifest. `android.permission.INTERNET`
   was declared only in the debug and profile manifests, so every release
   build (including the v0.2.0 APK) could not open sockets or resolve names.
   Fixed in the main manifest with a test that guards it. Host input is also
   normalised now (scheme, user@ prefix, brackets, trailing slash, whitespace)
   so a pasted `ssh://root@host:22` cannot reach the resolver as-is.

4. **Add-server auth selector.** The four-way segmented control wraps its
   labels onto two or three lines. Redesign with readable labels, a clear
   selected state, and default to Saved keys since most connects reuse an
   existing device key.
   Outcome: replaced by a 2x2 grid of selectable cards (icon, label, one-line
   hint). Saved key is the default and the most recent key is preselected.
