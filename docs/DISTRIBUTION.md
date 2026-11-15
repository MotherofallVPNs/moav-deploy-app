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
| F-Droid | Privacy-focused Android users | Built from source by F-Droid | Recipe builds in F-Droid's toolchain for v0.2.16; not yet submitted, see [F-Droid](#f-droid) |

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
- The in-app About screen (menu, issue #25) shows the version and the SHA-256
  fingerprint of the certificate that signed the installed APK, read from
  `PackageManager` at runtime through a method channel in `MainActivity.kt`.
  The release key's fingerprint should be published in the README and the
  release notes so users have something to compare against; that is a
  maintainer step once the keystore is final.

## F-Droid

Status: recipe validated against the F-Droid toolchain for v0.2.16
(versionCode 19); not submitted. Tracked in issue #24. The submission itself
is a manual merge request on GitLab, see [Submitting](#submitting).

F-Droid builds every app from source on its own servers, rejects proprietary
dependencies, and by default signs the result with its own key.

### Dependency audit

Last run against v0.2.16. No blocker and no anti-feature was found.

- `pubspec.lock`: 117 packages, all hosted on pub.dev or part of the Flutter
  SDK. No git or path dependencies.
- No Google Play Services, Firebase, Crashlytics, analytics, ads or other
  non-free SDK in `pubspec.yaml`, in the Gradle files, or in the dex of the
  released APK. Every artifact on the release runtime classpath is AndroidX,
  Kotlin, the Flutter engine, or a small free library (Tink, Gson, Guava
  `listenablefuture`, error-prone annotations, JSR-305, JSpecify, ReLinker).
- Native code in the APK: `libflutter.so` and `libapp.so` (Flutter engine and
  the compiled app) and `libdartjni.so`, built from source by the NDK from the
  `jni` package that newer Flutter plugins use.
- Plugins with Android code (`flutter_secure_storage`, `local_auth_android`,
  `webview_flutter_android`, `share_plus`, `url_launcher_android`,
  `path_provider_android`, `package_info_plus`) only depend on AndroidX.
  `webview_flutter` renders through the device's system WebView, which is a
  platform component, not an app dependency.
- Network: the app opens SSH sessions to the user's own server, loads that
  server's admin and Grafana pages, and sends one HTTPS login request to that
  Grafana. It contacts nothing else on its own, has no update checker and
  never downloads code.
- The F-Droid source scanner passes. The repo holds no `.jar`, `.aar` or
  other prebuilt binary; everything the scanner flags sits under `.pub-cache`
  (test archives and example projects of dependencies) and is dropped by
  `scandelete`.

### Anti-features and donations

None apply.

- The Support sheet links to Stripe and Buy Me a Coffee. Both open in the
  system browser through `url_launcher`; no payment SDK is bundled. F-Droid
  does not treat an external donation link as an anti-feature.
- The recipe carries an optional `Donate:` field with the same Stripe link,
  which F-Droid shows as a donate button on the listing. Drop the line to
  list without one.
- The "Donate configs" feature talks to MahsaNet from the user's server
  through the MoaV CLI, not from the app, and is optional, so `NonFreeNet`
  does not apply.

### Metadata

F-Droid reads the same Triple-T / fastlane layout that Play uses, straight
from the app repo at the tagged commit:

- `fastlane/metadata/android/<locale>/title.txt`, `short_description.txt`,
  `full_description.txt` for all seven locales (shared with Play, unchanged).
  Every short description fits F-Droid's 80 character summary limit.
- `fastlane/metadata/android/en-US/changelogs/<versionCode>.txt` per release.
  F-Droid ignores `default.txt`, so copy it to the numbered file at each
  release (`19.txt` for `0.2.16+19`).
- `fastlane/metadata/android/en-US/images/icon.png` (512 px) and eight
  `images/phoneScreenshots/`. The Play lanes skip image upload, so these never
  reach Play.
- Still missing and optional: `images/featureGraphic.png` (1024x500).

### Build recipe

The recipe lives at
[`docs/fdroid/org.motherofallvpns.moavdeploy.yml`](fdroid/org.motherofallvpns.moavdeploy.yml)
and follows fdroiddata's Flutter template. fdroiddata wants recipes without
comments, so the notes are here:

- `commit` is the full hash of the release tag, as fdroiddata requires.
- Flutter comes from the `flutter` srclib, which is the upstream Flutter git
  repo, so any Flutter tag can be built. The recipe reads the version from
  the first `flutter-version:` line in `.github/workflows/release.yml` and
  checks that tag out. A Flutter bump in CI therefore reaches F-Droid with
  the next tag and the recipe needs no edit.
- `flutter pub get --enforce-lockfile` runs in `prebuild` with the pub cache
  inside the build directory, so the scanner sees every Dart dependency.
  `pubspec.lock` must stay committed and in sync with `pubspec.yaml`.
- The source is moved to `/home/runner/work/moav-deploy-app/moav-deploy-app`
  for `pub get` and the build, the path `release.yml` builds in. The Dart
  snapshot embeds that path, so this is what makes `libapp.so` come out
  identical to the GitHub Release build.
- fdroidserver removes the `signingConfigs` block by itself. The `sed` line
  then drops the four-line `signingConfig = if (...)` assignment in
  `android/app/build.gradle.kts` so the APK comes out unsigned, and the
  `test` line fails the build if that assignment ever changes shape. Update
  both together with the Gradle file.
- `AutoUpdateMode: Version` with `UpdateCheckMode: Tags` makes F-Droid pick up
  each new `vX.Y.Z` tag by reading `version: X.Y.Z+N` from `pubspec.yaml`.
  No merge request is needed per release.

The copy in this repo is the reference; the one that matters is the merge
request on [fdroiddata](https://gitlab.com/fdroid/fdroiddata).

### Validating the recipe

[`scripts/fdroid-validate.sh`](../scripts/fdroid-validate.sh) runs the same
steps as the fdroiddata merge request pipeline inside F-Droid's buildserver
image. It needs Docker and nothing else.

```
scripts/fdroid-validate.sh lint    # fdroid lint, rewritemeta, checkupdates
scripts/fdroid-validate.sh build   # full fdroid build of the latest entry
```

`build` leaves the unsigned APK in `build/fdroid/` and prints how it differs
from the signed GitHub Release APK of the same version. The
`F-Droid recipe` workflow runs both modes on every pull request that touches
the recipe, the script or the workflow.

The image is amd64 only. On Apple Silicon `lint` works, but `build` stops at
the Dart compile step because the Dart VM aborts under Rosetta
(`Unexpected EINTR errno`). Use the pull request check or an x86_64 Linux
host for the build.

Results for v0.2.16 (versionCode 19): lint, rewritemeta and checkupdates are
clean, and `fdroid build` passes, including the source scanner.

### Signing: three different keys

- Google Play installs are signed by Google (Play App Signing). The team
  holds only the upload key.
- GitHub Release and mirrored APKs are signed with that upload key. Its
  certificate SHA-256, read from the v0.2.16 release APK with
  `apksigner verify --print-certs`, is
  `bbd565a138fe28831673f78659eca2c3139d6b862116c8a1b8bb9d7196f80aa6`.
- An F-Droid-built APK is signed by F-Droid's key.

Android treats each as a different app for update purposes, so a Play
install, a sideloaded APK and an F-Droid install cannot update one another.
Users must uninstall and reinstall to switch channels, which also wipes the
stored servers and keys; say so in the F-Droid description once listed.

The way out is reproducible builds. When F-Droid's build is byte-identical
to our GitHub Release APK, F-Droid ships our signed APK instead. F-Droid and
sideload installs then share one signature; Play stays separate because
Google re-signs.

This has to be decided before the app is first published. fdroiddata's
merge request template states that an app first shipped with F-Droid's key
cannot switch to the developer's key later.

### Reproducible builds: where we stand

Measured on v0.2.16 by comparing the F-Droid build with the signed GitHub
Release APK entry by entry:

- 489 of 492 entries are identical, in the same order.
- The three that differ are `lib/<abi>/libdartjni.so`, and only in their
  20-byte ELF build ID. That ID is a hash over the linker's input; the likely
  cause is absolute paths that differ between the two hosts (NDK and pub
  cache locations).
- The v0.2.16 release APK also carries AGP's "Dependency metadata" signing
  block, a Google-encrypted dependency list that fdroidserver's APK scanner
  counts as a problem in developer-signed APKs. `dependenciesInfo
  { includeInApk = false }` in `android/app/build.gradle.kts` removes it from
  the next release on. The Play AAB is not affected.

So v0.2.16 cannot be the reference binary, and reproducible mode can start
with the first release that has both fixes. What is left:

1. Drop the build ID from `libdartjni.so` on both sides with the line many
   Flutter recipes in fdroiddata use (not yet tried on this app). In
   `release.yml`, after `flutter pub get` in the Android job:

   ```
   sed -i -e 's/-Wl,/-Wl,--build-id=none,/' "${PUB_CACHE:-$HOME/.pub-cache}"/hosted/pub.dev/jni-*/src/CMakeLists.txt
   ```

   and in the recipe's `prebuild`, after `pub get`:

   ```
   - sed -i -e 's/-Wl,/-Wl,--build-id=none,/' $PUB_CACHE/hosted/pub.dev/jni-*/src/CMakeLists.txt
   ```

2. Cut the release, point the recipe at it and run
   `scripts/fdroid-validate.sh build`. It must report no differing entries.
3. Add to the build entry and to the top level of the recipe:

   ```
       binary: https://github.com/MotherofallVPNs/moav-deploy-app/releases/download/v%v/app-release.apk
   AllowedAPKSigningKeys: bbd565a138fe28831673f78659eca2c3139d6b862116c8a1b8bb9d7196f80aa6
   ```

   With `binary` set, `fdroid build` downloads the release APK and fails if
   its own build does not match, so the check in step 2 becomes automatic.

Things that keep this working once enabled: `release.yml` and the recipe must
build with the same Flutter (the recipe reads it from `release.yml`), the
release APK must be attached to the GitHub Release under the name
`app-release.apk`, and the upload key must not change. A release that does
not reproduce is simply not published by F-Droid until it is fixed.

### Submitting

The submission is a merge request against
[fdroiddata](https://gitlab.com/fdroid/fdroiddata) on GitLab and is done by
hand:

1. Sign in to gitlab.com and fork `fdroid/fdroiddata`. The fork must be
   public.
2. On a new branch, copy the recipe to
   `metadata/org.motherofallvpns.moavdeploy.yml`. Nothing else goes in the
   merge request; listing text and images are read from this repo.
3. Open a merge request titled `New app: MoaV Deploy` and fill in the
   template's checklist. State whether reproducible builds are enabled and,
   if not, why.
4. Wait for the pipeline, then answer the reviewers. Likely requests are an
   `ndk:` line and per-ABI APKs (the fat APK is about 70 MB, a single ABI
   about 25 MB), which would add `--split-per-abi` and `VercodeOperation` to
   the recipe and, in reproducible mode, per-ABI assets to the GitHub
   Release.

After the merge, F-Droid builds and signs on its own schedule, so the listing
usually appears a few days later. New versions are picked up from tags
without another merge request.

### Remaining steps

1. Decide the signing route: F-Droid's key (works today, three keys for
   good) or reproducible (two keys, needs the steps above and one more
   release).
2. Confirm the optional `Donate:` link and the categories in the recipe.
3. Open the fdroiddata merge request.
4. Add the F-Droid badge to the README next to Google Play once listed.
5. Publish the release certificate fingerprint in the README and release
   notes so sideload and F-Droid users can compare it with the About screen.

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
