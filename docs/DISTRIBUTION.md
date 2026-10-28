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
| F-Droid | Privacy-focused Android users | Built from source by F-Droid | Groundwork done (dependency audit, metadata, recipe draft); not yet submitted, see [F-Droid](#f-droid) |

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

## F-Droid

Status: groundwork done, not submitted. Tracked in issue #24.

F-Droid builds every app from source on its own servers, rejects proprietary
dependencies, and by default signs the result with its own key. What is in
place and what is still missing:

### Dependency audit

The Android release runtime classpath was listed with
`./gradlew :app:dependencies --configuration releaseRuntimeClasspath` and the
debug APK dex was scanned. Nothing from Google Play Services, Firebase or any
other non-free SDK is present. Every Gradle artifact is AndroidX, Kotlin,
the Flutter engine, or Apache-2 Google libraries (Tink, Gson, Guava
`listenablefuture`, error-prone annotations, JSR-305). Pure-Dart packages
(`dartssh2`, `pinenacl`, `cryptography`, `fl_chart`, `qr_flutter`,
`flutter_riverpod`) add no native code. Plugins with Android code
(`flutter_secure_storage`, `local_auth_android`, `webview_flutter_android`,
`share_plus`, `url_launcher_android`, `path_provider_android`) only depend on
AndroidX. `webview_flutter` renders through the device's system WebView,
which is a platform component, not an app dependency. The only `.jar` in the
tree is the Gradle wrapper, which the F-Droid scanner allow-lists. No
blocker was found.

### Metadata

F-Droid reads the same Triple-T / fastlane layout that Play uses, straight
from the app repo at the tagged commit:

- `fastlane/metadata/android/<locale>/title.txt`, `short_description.txt`,
  `full_description.txt` for all seven locales (shared with Play, unchanged).
- `fastlane/metadata/android/en-US/changelogs/<versionCode>.txt` per release.
  F-Droid ignores `default.txt`, so keep writing the numbered file at each
  release as [RELEASING.md](RELEASING.md) already requires.
- `fastlane/metadata/android/en-US/images/icon.png` (512 px, added for
  F-Droid). The Play lanes skip image upload, so this never reaches Play.
- Still missing and optional: `images/featureGraphic.png` (1024x500) and
  `images/phoneScreenshots/`. Add them when Android screenshots exist; they
  will not be uploaded to Play either.

### Build recipe

A draft of the fdroiddata recipe lives at
[`docs/fdroid/org.motherofallvpns.moavdeploy.yml`](fdroid/org.motherofallvpns.moavdeploy.yml).
It pins the Flutter srclib, strips the release `signingConfig` so the APK
comes out unsigned, builds `flutter build apk --release`, and auto-updates
from `vX.Y.Z` tags by reading `version: X.Y.Z+N` in `pubspec.yaml`. The copy
in this repo is for reference; the one that matters is the merge request on
[fdroiddata](https://gitlab.com/fdroid/fdroiddata).

### Signing: three different keys

- Google Play installs are signed by Google (Play App Signing). The team
  holds only the upload key.
- GitHub Release and mirrored APKs are signed with that upload key.
- An F-Droid-built APK is signed by F-Droid's key.

Android treats each as a different app for update purposes, so a Play
install, a sideloaded APK and an F-Droid install cannot update one another.
Users must uninstall and reinstall to switch channels, which also wipes the
stored servers and keys; say so in the F-Droid description once listed.

The way out is reproducible builds. When F-Droid's build is byte-identical
to our GitHub Release APK, the recipe gains `Binaries:` and
`AllowedAPKSigningKeys:` and F-Droid ships our signed APK instead. F-Droid
and sideload installs then share one signature; Play stays separate because
Google re-signs.

### Reproducibility considerations

- Pinned already: Gradle 9.3.1 (wrapper), AGP 9.1.0, Kotlin 2.4.0, every Dart
  package via the committed `pubspec.lock`.
- Not pinned yet: the Flutter version. `release.yml` uses the `stable`
  channel, so the artifact depends on whatever stable is on release day.
  The recipe pins `flutter@3.47.4`, the version this groundwork was verified
  with; the release workflow must pin the same version before the
  `Binaries:` route can work. Changing CI is out of scope for the groundwork
  and is listed below.
- The Flutter tool downloads the Dart SDK and prebuilt engine artifacts on
  first run; F-Droid accepts this for Flutter apps via the `flutter` srclib.
- Fat APK: the recipe builds a single multi-ABI APK, matching the release
  asset. `--split-per-abi` is possible later as separate build entries.
- Same-host check done: two `flutter build apk --release` runs on one macOS
  host (Flutter 3.47.4, `flutter clean` in between, signing block stripped
  as in the recipe) produced byte-identical unsigned APKs. Cross-host
  comparison (F-Droid's Linux build server vs the CI runner) is still to be
  done.
- AGP writes `META-INF/version-control-info.textproto` into the APK with the
  git revision. Same commit gives the same content, but a checkout AGP cannot
  read as git (worktrees, exported tarballs) records "no VCS" instead. If
  cross-host hashes differ only there, set `android.vcsInfo.include = false`
  in `android/app/build.gradle.kts`.

### Remaining steps

1. Pin the Flutter version in `release.yml` to the one in the recipe, and
   bump both together on every Flutter upgrade.
2. Verify two CI runs (or CI vs a local `fdroid build`) produce the same
   `app-release.apk` SHA-256. Fix any drift before step 3.
3. Decide the channel: F-Droid key (simpler, three keys) or reproducible with
   `Binaries:` (recommended, two keys). For the latter, record the upload
   certificate fingerprint from `apksigner verify --print-certs` in
   `AllowedAPKSigningKeys`.
4. Open the fdroiddata merge request with the recipe; run `fdroid lint` and
   `fdroid build org.motherofallvpns.moavdeploy` locally first.
5. Add the F-Droid badge to the README next to Google Play once listed.
6. Sideload verification (#25) should land first so users can compare what
   they installed against the published fingerprint.

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
