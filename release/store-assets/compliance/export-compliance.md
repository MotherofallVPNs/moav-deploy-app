# Export compliance (encryption)

Not legal advice. This is the reasoning behind the answers, so the person
who clicks through App Store Connect can check it against the current
wording of the questions.

## What encryption the app contains

| Use | Implementation | Standard? |
|---|---|---|
| SSH transport to the user's server | `dartssh2` (pure Dart) with `pinenacl` and `pointycastle` | Yes: SSH-2 with Curve25519, Ed25519, AES, ChaCha20-Poly1305 |
| Ed25519 key generation for SSH login | `pinenacl` | Yes |
| Passphrase-encrypted SSH key backup | `cryptography` | Yes: PBKDF2 key derivation, AES-256-GCM |
| HTTPS inside the WebView and for the tunnelled Grafana sign-in | OS TLS stack (WKWebView, Android WebView, `dart:io`) | Yes |
| Secrets at rest | iOS Keychain, Android Keystore via `flutter_secure_storage` | OS-provided |
| Disguise passcode hash | PBKDF2-HMAC-SHA256 (`cryptography`) | Yes |

No proprietary or non-standard algorithm. The app does not itself provide a
VPN or encrypt the phone's traffic. The VPN protocols run on the server;
the app only starts and stops them over SSH.

One point matters for the Apple questionnaire: the SSH cryptography is
implemented in Dart inside the app. It is not only a call into Apple's own
crypto. That puts the app in the group "standard encryption algorithms
instead of, or in addition to, the encryption in Apple's operating system".

## App Store Connect

`ios/Runner/Info.plist` already sets `ITSAppUsesNonExemptEncryption` to
`false`, so uploads skip the questionnaire and each build shows "Export
compliance: not required". That is why TestFlight builds have gone through
without a prompt.

The declaration is defensible: all encryption is standard, published and
used for authentication and a secure channel to the user's own server. Such
mass-market software qualifies for the exemption in Category 5 Part 2 of the
US Export Administration Regulations, and the source is public under MIT.

If the questionnaire is ever shown (for example after removing the plist
key), the answers are:

1. Does your app use encryption? **Yes.**
2. Does it qualify for any of the exemptions in Category 5, Part 2 of the
   US EAR? **Yes.**
3. Does it implement any proprietary or non-standard encryption algorithms?
   **No.**
4. Does it implement standard encryption algorithms instead of, or in
   addition to, using or accessing the encryption in Apple's operating
   system? **Yes** (the Dart SSH stack).

### France

Apple's documentation ties answer 4 to one extra requirement: an app with
its own implementation of standard encryption needs a French encryption
declaration (ANSSI) before it is distributed on the App Store in France.
Two ways to handle it, pick one before release:

- **Simplest:** leave France out of the availability list for the first
  release and add it once the declaration is filed.
- **Complete:** file the ANSSI declaration (a form, no fee, typically a few
  weeks), upload the approval in App Store Connect under App Information,
  Encryption, and put the resulting code in `ITSEncryptionExportComplianceCode`.

Check Apple's current "Complying with Encryption Export Regulations" page
when you do this; the France rule has been revised before.

### US year-end self-classification report

Mass-market software under ECCN 5D992.c that uses only standard cryptography
no longer needs the annual self-classification report to BIS (rule change of
March 2021). Nothing to file.

## Google Play

Play has no per-app encryption questionnaire. Uploading to Play means
accepting US export law under the Developer Distribution Agreement; the same
5D992.c mass-market reasoning applies. No form to fill in.

## Country availability and VPN rules

Separate from encryption, but decided on the same screen:

- **China mainland:** apps that deliver VPN functionality need a licence
  from MIIT, and Apple asks for it. MoaV Deploy is an administration tool,
  not a VPN client, but the listing is about circumvention. Recommended:
  exclude China mainland on both stores rather than argue the point in
  review.
- **Russia:** both stores have removed VPN apps on regulator request. The
  app can be listed; expect a possible takedown notice later. The sideload
  channels in `docs/DISTRIBUTION.md` exist for this.
- **Iran:** neither store serves Iran directly. No setting to change.
