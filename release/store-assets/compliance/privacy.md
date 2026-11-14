# Privacy: policy URL, Play Data safety, App Store privacy labels

Answers below come from reading the code at v0.2.15 (commit `8dc6cb0`), not
from the marketing copy. The evidence table at the end lists where each
claim was checked. Re-check it when a dependency or a network call is added.

## Short version

| Question | Answer |
|---|---|
| Privacy policy URL (both stores) | `https://moav.sh/docs/deploy/privacy/` (live, HTTP 200) |
| Play Data safety: does the app collect or share user data? | **No** |
| App Store privacy label | **Data Not Collected** |
| Tracking (ATT prompt, advertising ID) | None. No ATT prompt, no `AD_ID` permission |
| Account required | No. There is no account system |
| Data deletion | Emergency wipe in the app, or uninstall. Nothing exists server-side to delete |

## What the app handles, and where it goes

| Data | Where it lives | Leaves the phone? |
|---|---|---|
| Server host, port, username, label | Platform secure storage (iOS Keychain, Android Keystore-wrapped) | Only as the destination of the SSH connection the user starts |
| SSH private keys, SSH passwords | Platform secure storage. iOS: `first_unlock_this_device`, iCloud sync off | A private key is used on the phone to sign in and is never sent. It leaves only if the user exports a passphrase-encrypted backup (AES-256-GCM) through the share sheet. A password is sent only inside the SSH handshake to the user's own server |
| Install job handle (job id, log path) | Platform secure storage | No |
| Disguise mode passcode | PBKDF2 hash in secure storage | No |
| Disguise mode notes | Plain JSON file in the app's support directory | No |
| VPN user names and connection bundles | Fetched from the user's server over SSH/SFTP, held in memory. A temp file is written only when the user taps Share | Only where the user sends it through the system share sheet |
| Server metrics, logs, health checks | Read over SSH, shown, not stored | No |
| Grafana and admin panel pages | Loaded in an in-app WebView through an SSH tunnel on the loopback interface | No. Cookies stay in the app's WebView store and are cleared by the emergency wipe |
| Biometrics | Handled by the OS (`local_auth`); the app only gets yes or no | No |
| Clipboard | Written when the user taps Copy; cleared by the emergency wipe | No |

The developer (MotherofallVPNs) receives nothing. There is no backend, no
analytics SDK, no crash reporter and no remote config. The only network
peers are the servers the user adds.

Links that open the system browser (docs, GitHub, X, Telegram, the
"Support us" sheet with Stripe Checkout, GitHub Sponsors and Buy Me a
Coffee) use `LaunchMode.externalApplication`. Whatever those sites collect
happens in the browser under their own policies, outside the app. The
Stripe donation is a hosted checkout page; no payment SDK is in the app and
the app never sees card or wallet data.

## Google Play: Data safety form

Play Console, App content, Data safety.

1. **Does your app collect or share any of the required user data types?**
   No.
2. That answer ends the form. Play shows "No data collected" and "No data
   shared with third parties" on the listing.

Why "No" holds:

- Play counts data as collected when the app transmits it off the device to
  the developer or a third party. Data processed only on the device does not
  count. Everything in the table above stays on the device or goes to a
  server the user owns and typed in.
- The SSH session is user-initiated and its destination is the user's own
  machine. The developer is not a party to it and cannot see it.
- No SDK in the build collects anything. The dependency audit in
  `docs/DISTRIBUTION.md` found no Play Services, Firebase or other
  analytics/ads library in the release classpath.

Judgement call to be aware of: the form has no explicit exemption for "a
server the user owns". If Google ever treats the SSH login as collection
because credentials cross the network, the fallback is to declare one data
type (Personal info, Other info) as collected, not shared, encrypted in
transit, required, purpose App functionality. Do not volunteer this; it
describes the same behaviour less accurately.

Related declarations in the same App content section:

| Declaration | Answer |
|---|---|
| Ads | No, the app contains no ads |
| App access | All functionality is available without special access. Add the note: "No login. Open the app, tap Add server, then Try a demo server to explore every screen with emulated data." |
| Advertising ID | No. The app does not use an advertising ID |
| Government app | No |
| Financial features | None |
| Health | None |
| News app | No |
| Target audience | 18 and over. The app is a server administration tool, not aimed at children |

## App Store: App Privacy

App Store Connect, App Privacy.

1. **Privacy Policy URL**: `https://moav.sh/docs/deploy/privacy/`
2. **Do you or your third-party partners collect data from this app?**
   No, we do not collect data from this app.
3. Result: the "Data Not Collected" label.

Why it holds: Apple defines collection as transmitting data off the device
in a way that lets the developer or its partners access it. Nothing reaches
the developer or a partner. Data sent to the user's own server is not
developer access, and the web pages opened in Safari are outside the app.

No App Tracking Transparency prompt is needed and none is implemented.

Privacy manifest: the app target has no `PrivacyInfo.xcprivacy` of its own.
The Flutter engine and the plugins ship theirs. TestFlight uploads have gone
through, so there is no blocking error today; if an upload email ever lists
ITMS-91053 (missing required-reason API declaration), add a manifest to the
Runner target then.

## Gaps worth closing (none block submission)

1. **No privacy policy link inside the app.** Apple guideline 5.1.1(i) asks
   for the policy to be reachable in the app as well as in the listing. The
   menu has Documentation and About but no direct privacy link. Low risk for
   an app that collects nothing, and a one-line fix (a "Privacy policy" row
   on the About screen) for the next build.
2. **The policy page does not mention the outbound links.** One sentence
   would cover it: "Links to our docs, source code and donation pages open
   in your browser; those sites have their own privacy policies." That is an
   edit in the docs repo, not here.
3. **Android Auto Backup is at its default.** Secure-storage entries are
   wrapped by a Keystore key that does not restore to another device, so
   credentials do not travel, but the disguise-mode notes file can be
   included in a Google backup. Not a Data safety item (the developer never
   receives it); mentioned so the "nothing leaves the phone" claim is exact.

## Evidence

| Claim | Checked in |
|---|---|
| Android permissions: `INTERNET`, `USE_BIOMETRIC`, `USE_FINGERPRINT` (legacy biometric, from `local_auth`). No `AD_ID` | `aapt2 dump badging` on the released v0.2.15 `app-release.apk` |
| iOS usage strings: Face ID only | `ios/Runner/Info.plist` (`NSFaceIDUsageDescription`) |
| No entitlements file, so no NetworkExtension, push or iCloud | `ios/Runner/` |
| Secrets in secure storage, iCloud sync off | `lib/security/secure_cred_store.dart` |
| Only socket use is SSH plus a loopback tunnel listener | `lib/core/ssh_connection.dart`, `lib/core/ssh_tunnel.dart` |
| Only HTTP client call is the Grafana sign-in through that tunnel | `lib/core/grafana_login.dart` |
| WebViews load only the tunnelled Grafana and admin pages | `lib/features/operate/grafana_screen.dart`, `lib/features/admin/admin_panel_screen.dart` |
| Every outbound link opens the external browser | all `launchUrl` calls use `LaunchMode.externalApplication` |
| Donation is a hosted Stripe Checkout URL, no payment SDK | `lib/core/moav_links.dart`, `pubspec.yaml` |
| No telemetry or crash reporter | `lib/main.dart`, `pubspec.yaml` (no analytics or crash packages) |
| Demo server opens no connection | `lib/core/demo_moav_controller.dart`, `lib/core/moav_controller_factory.dart` |
| Wipe clears servers, keys, WebView cookies and cache, clipboard | `lib/security/wipe_service.dart` |
| Key backup export is passphrase-encrypted and user-initiated | `lib/security/key_export_service.dart`, `lib/features/keys/keyring_screen.dart` |
