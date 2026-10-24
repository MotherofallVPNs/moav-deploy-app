# Deployment: building and running MoaV Deploy

This is the app-side guide (build, run, sign). For how the app deploys MoaV
onto a server, see `docs/ARCHITECTURE.md` and `lib/core/install_script.dart`.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Flutter | 3.32+ stable (CI uses latest stable; developed on 3.47) | `flutter --version` |
| Dart | bundled with Flutter (SDK ^3.8) | |
| Xcode | 16+ | iOS builds, TestFlight uploads |
| Android Studio / SDK | API 35 SDK, JDK 17 | Android builds |
| CocoaPods | latest | `sudo gem install cocoapods` |

Identifiers: bundle id / application id is `org.motherofallvpns.moavdeploy`
on both platforms (`android/app/build.gradle.kts`, `ios/Runner.xcodeproj`).
iOS deployment target is 15.0.

## Run locally

```
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter run -d <device>        # iPhone / Android device or simulator
```

The app has no backend. Everything it needs is a MoaV server reachable over
SSH. For a dev loop, point it at a throwaway VPS, or at the shared test box
`yorkschool.xyz` using a key that is already in its `authorized_keys`.

Biometric app lock is on by default; it falls back to device passcode and is
skipped on simulators without enrolled biometrics.

## Live integration tests

Tests tagged `live` (`test/live/`) talk to a real MoaV box. They are skipped
unless env vars are set and are **never** run in CI:

```
MOAV_TEST_SSH_KEY=~/.ssh/moav_deploy_app_ed25519 \
MOAV_TEST_HOST=yorkschool.xyz MOAV_TEST_USER=root \
flutter test test/live
```

They are additive only: they create users named `zzmoavdeploytest<pid>`,
verify, and revoke them; they never start/stop services or touch existing
users. `live_ssh_test.dart` re-runs the installer to prove idempotence on an
already-installed box.

## Build artifacts

### Android

```
flutter build apk --release                # sideloadable APK
flutter build appbundle --release          # Play Store AAB
```

Release signing is wired: `android/app/build.gradle.kts` reads a git-ignored
`android/key.properties` and signs release builds with the upload keystore;
if `key.properties` is absent (CI, fresh clones) it falls back to debug
signing so builds still succeed.

We use **Play App Signing**: Google holds the real app-signing key, we hold
only the upload key. This keeps the Play upload key separate from the APK
sideload trust path. The keystore must be PKCS12 and its store and key
passwords must be identical (PKCS12 does not support per-entry passwords).

Create the upload keystore once, outside the repo:

```
keytool -genkeypair -v -keystore <path>/moav-deploy-upload.jks \
  -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then add `android/key.properties` (git-ignored) pointing at it:

```
storePassword=…
keyPassword=…        # same as storePassword for PKCS12
keyAlias=upload
storeFile=<path>/moav-deploy-upload.jks
```

The maintained keystore + credentials live outside the repo on the build
host; ask the owner for their location. Verify a built artifact with
`jarsigner -verify build/app/outputs/bundle/release/app-release.aab`.

### iOS

```
flutter build ipa --release --export-method app-store   # TestFlight / App Store
flutter build ipa --release --export-method ad-hoc      # registered devices
```

Signing uses Xcode automatic signing with the MotherofallVPNs team; set
`DEVELOPMENT_TEAM` in Xcode once (Runner target › Signing & Capabilities).
Required capabilities: none beyond default. `NSFaceIDUsageDescription` is
already in `Info.plist`.

## Versioning

`pubspec.yaml` `version: X.Y.Z+N` drives both platforms. Bump `N` (build
number) on every store upload; bump `X.Y.Z` per release. CI does not tag
releases yet; see `docs/WORKFLOW.md`.

## Runtime requirements on the server side

- SSH reachable (default port 22) with either the app's ed25519 key in
  `authorized_keys` or password auth for the one-time key install.
- MoaV v2.2.x. Older versions may print different `user list` / `status`
  text; the parsers in `lib/core/moav_cli.dart` are verified against 2.2.2.
- For monitoring: the `monitoring` profile running (Grafana on
  `PORT_GRAFANA`, default 9444). Headline metrics are read from Prometheus
  via `docker exec`, so the app needs a user that can run `docker` (root).

## Secrets hygiene

- Private keys live only in the platform secure store; the app never writes
  them to disk elsewhere and never sends them anywhere but the SSH handshake.
- Nothing in the repo contains server credentials. Live-test keys are read
  from `MOAV_TEST_SSH_KEY` at runtime.
- Test fixtures under `test/fixtures/` are sanitized captures (example
  hostnames and RFC 5737 addresses).
