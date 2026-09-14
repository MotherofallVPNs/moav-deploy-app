# Distribution: App Store, Play, and sideload paths

MoaV exists for people behind national firewalls. Many of them cannot reach
the official app stores, or cannot safely be seen installing a VPN manager.
So we ship through **every** channel, and the sideload paths are first-class,
not a fallback.

## Channels

| Channel | Who it serves | Artifact | Status |
|---|---|---|---|
| Apple App Store | iOS users with store access | `.ipa` via App Store Connect | P1 target |
| TestFlight (public link) | iOS beta + regions where the listing may be pulled | same build | P1 target (M5) |
| Google Play (internal → production) | Android users with store access | `.aab` | P1 target |
| Direct APK on GitHub Releases | censored regions, de-Googled phones | `.apk` (arm64 + universal) | P1 target (M5) |
| APK mirror via MoaV website / Telegram channel | users who cannot reach GitHub | same `.apk` + SHA-256 | with MoaV team |
| F-Droid | privacy-focused Android users | reproducible build from source | P2, needs no proprietary deps |

## App Store (iOS)

- Category: Utilities (or Developer Tools). It is a **server administration**
  app, not a VPN client, and it does not use the NetworkExtension entitlement.
  Say so plainly in the review notes: "Manages the user's own MoaV server
  over SSH. Does not route traffic. No VPN configuration is installed."
- Provide a review account: a throwaway MoaV VPS with a pre-installed key,
  or a password login, plus a short video of the flow.
- Privacy nutrition label: **no data collected**. There is no analytics,
  crash reporting, or backend.
- Export compliance: the app uses standard SSH (dartssh2) and TLS only;
  answer "uses encryption, exempt" under the standard exemption.
- Expect questions about "VPN" in the name. Keep marketing copy about
  *managing* a server.

## Google Play (Android)

- Data safety form: no data collected or shared.
- Declare `USE_BIOMETRIC` only; no `INTERNET`-restricted permissions beyond
  network access.
- Release track flow: internal testing → closed testing (Telegram beta group)
  → production. Staged rollout 20 % → 100 %.
- The listing may be geo-blocked in some countries by Google; the APK path
  below covers that.

## TestFlight

- Use a **public** TestFlight link for the beta so at-risk users do not have
  to give us an email address.
- 90-day build expiry: automate uploads (see `docs/WORKFLOW.md`) so a build
  is always fresh.

## Direct APK / sideload

- Publish on GitHub Releases with the SHA-256 and a minisign/GPG signature.
  The signing public key goes in the README and on moav.sh so users can
  verify a mirrored APK.
- Build both `--split-per-abi` (smaller, arm64-v8a is the common one) and a
  universal APK.
- Keep the APK signing key **separate** from the Play upload key so a Play
  account compromise does not affect sideload trust.
- The in-app "About" screen should show the version and the APK signature
  fingerprint so users can compare against the published one (M5).

## Naming and at-risk users

- The listing name is "MoaV Deploy". If a store rejects on the name, use
  "Server Manager for MoaV" rather than dropping the project name.
- The app never phones home, so there is no server-side kill switch and no
  way for us to see who runs it. Document this in the listing; it matters to
  our users.
- Offer a "quick wipe" (M5) prominently in store screenshots: device seizure
  is part of the threat model.

## Checklist before a store submission

1. `flutter analyze --fatal-infos && flutter test` green on `main`.
2. Live tests pass against `yorkschool.xyz` for the release commit.
3. Version bumped in `pubspec.yaml`; changelog entry in the GitHub Release.
4. Screenshots refreshed for both platforms (6.7" and 5.5" iPhone, phone +
   7" tablet Android).
5. Review notes updated with a working test server.
