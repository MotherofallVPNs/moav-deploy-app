# Distribution: stores and sideload paths

MoaV exists for people behind national firewalls. Many of them cannot reach
the official app stores, or cannot safely be seen installing a VPN manager.
So the app ships through every channel it can, and the sideload paths are
first-class, not a fallback.

## Channels

| Channel | Who it serves | Artifact | Status |
|---|---|---|---|
| Google Play | Android users with store access | `.aab` | Closed testing track, uploaded by CI on each release; promoted to open testing and production by hand |
| GitHub Releases | Censored regions, de-Googled phones | signed `.apk` and `.aab` | Attached by CI on each release |
| Apple App Store | iOS users with store access | `.ipa` via App Store Connect | Not yet published |
| TestFlight | iOS beta, and regions where a listing may be pulled | same build | Internal testers get every release automatically via CI; public link not yet opened |
| APK mirror via moav.sh or Telegram | Users who cannot reach GitHub | same `.apk` plus SHA-256 | Coordinated with the MoaV team |
| F-Droid | Privacy-focused Android users | Reproducible build from source | Not started; needs no proprietary dependencies |

## Google Play

- Data safety form: no data collected or shared.
- Permissions: `INTERNET` and `USE_BIOMETRIC` only.
- Track flow: closed testing, then open testing, then production. Promotion to production is a
  manual step; see [RELEASING.md](RELEASING.md).
- The listing may be geo-blocked in some countries by Google. The APK path
  covers those users.
- Listing text for all locales lives under `fastlane/metadata/android/` and
  is pushed deliberately with `fastlane android sync_listing`.

## App Store

- Category: Utilities or Developer Tools. It is a server administration app,
  not a VPN client, and it does not use the NetworkExtension entitlement. Say
  so plainly in the review notes: "Manages the user's own MoaV server over
  SSH. Does not route traffic. No VPN configuration is installed."
- Provide a review account: a throwaway MoaV VPS with a pre-installed key, or
  a password login, plus a short video of the flow.
- Privacy nutrition label: no data collected. There is no analytics, crash
  reporting or backend.
- Export compliance: the app uses standard SSH and TLS only; answer "uses
  encryption, exempt" under the standard exemption.
- Expect questions about "VPN" in the name. Keep marketing copy about
  managing a server.

## TestFlight

- Use a public TestFlight link for the beta so at-risk users do not have to
  hand over an email address.
- Builds expire after 90 days, so uploads are automated: every published
  GitHub Release runs the `ios beta` Fastlane lane on a macOS runner and
  uploads the build to TestFlight internal testers. Signing comes from
  fastlane match; see [RELEASING.md](RELEASING.md#ios).
- Adding an external group or opening the public link is a manual step in
  App Store Connect and triggers Apple's TestFlight review.

## Direct APK and sideload

- Every GitHub Release carries the signed APK and AAB plus a `SHA256SUMS`
  file written by `release.yml`. A mirrored APK is checked with
  `sha256sum -c SHA256SUMS` in the download directory. A minisign or GPG
  signature is still to come once a signing key is chosen, with the public
  key in this README and on moav.sh.
- Keep the APK signing key separate from the Play upload key so a Play
  account compromise does not affect sideload trust.
- An in-app About screen showing the version and the APK signature
  fingerprint would let users compare against the published one.

## Naming and at-risk users

- The listing name is "MoaV Deploy". If a store rejects the name, use "Server
  Manager for MoaV" rather than dropping the project name.
- The app never phones home, so there is no server-side kill switch and no
  way for the project to see who runs it. Say this in the listing; it
  matters to the people the app is for.
- Device seizure is part of the threat model. The emergency wipe should be
  visible in store screenshots.

## Checklist before a store submission

1. `flutter analyze --fatal-infos && flutter test` green on `main`.
2. Live tests pass against a current MoaV server for the release commit.
3. Version bumped in `pubspec.yaml`; release notes updated in
   `fastlane/metadata/android/en-US/changelogs/default.txt`.
4. Screenshots refreshed for both platforms.
5. Review notes updated with a working test server.
