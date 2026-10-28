# Building and running MoaV Deploy

This is the app-side guide: toolchain, running locally, signing, live tests,
and what the app expects on the server. How the app installs MoaV onto a
server is covered in [ARCHITECTURE.md](ARCHITECTURE.md) and
`lib/core/install_script.dart`.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Flutter | 3.32 or newer, stable channel | CI uses the latest stable |
| Dart | bundled with Flutter (SDK 3.8 or newer) | |
| Xcode | 16 or newer | iOS builds and uploads |
| Android SDK | API 35 with JDK 17 | Android builds |
| CocoaPods | latest | iOS plugin dependencies |

The bundle id and application id are `org.motherofallvpns.moavdeploy` on both
platforms (`android/app/build.gradle.kts`, `ios/Runner.xcodeproj`). The iOS
deployment target is 15.0.

## Run locally

```
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter run -d <device>
```

The app has no backend. Everything it needs is a MoaV server reachable over
SSH. For a development loop, point it at a throwaway VPS, or at a server you
administer using a key that is already in its `authorized_keys`.

The biometric app lock is on by default. It falls back to the device passcode
and is skipped on simulators without enrolled biometrics.

## Live integration tests

Tests tagged `live` (`test/live/`) talk to a real MoaV server. They are
skipped unless the environment variables below are set. The regular CI job
never sets them; the opt-in live round that does is described in
[LIVE-CI.md](LIVE-CI.md).

```
MOAV_TEST_SSH_KEY=~/.ssh/your_key \
MOAV_TEST_HOST=your.server MOAV_TEST_USER=root \
flutter test test/live
```

Optional: `MOAV_TEST_PORT` (default 22) and `MOAV_TEST_DOMAIN` (defaults to
the host) for the install idempotence check.

They are additive only: they create users named `zzmoavdeploytest<pid>`,
verify, and revoke them; they never start or stop services or touch existing
users. `live_ssh_test.dart` re-runs the installer to prove idempotence on an
already-installed box. The full policy is in
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Screenshot gallery

`tool/screenshots.sh` drives the app on a booted iOS simulator through
`integration_test/screenshots_test.dart` and writes PNGs to `shots/`
(git-ignored). By default it uses built-in demo data. With the `MOAV_TEST_*`
variables above it talks to the real server, read-only except for one
throwaway `zzmoavdeploytest*` user created for the bundle shot and revoked
afterwards. A box that only has password auth works too: set
`MOAV_TEST_PASSWORD` instead of `MOAV_TEST_SSH_KEY` (the script base64-encodes
it into the `MOAV_TEST_PASSWORD_B64` define so shell metacharacters survive).

## Live end-to-end run

`tool/e2e_live.sh` drives the whole first-run flow through the real UI on a
booted iOS simulator against a disposable box, with password auth: add the
server, run the headless install from the Deploy screen, read the Services
and Health tabs, add a user, open the bundle and share its zip. It is not
read-only: it installs MoaV and leaves the user behind unless
`MOAV_TEST_E2E_CLEANUP=true`.

```
MOAV_TEST_HOST=1.2.3.4 MOAV_TEST_USER=root MOAV_TEST_PASSWORD='...' \
tool/e2e_live.sh ./e2e-evidence
```

Without `MOAV_TEST_DOMAIN` the install is domainless with the default
service selection; the installer disables the certificate-dependent
protocols itself (`MOAV_DOMAINLESS=1`). `MOAV_TEST_E2E_DESELECT` optionally
unticks profiles on the Deploy form (for example `proxy,dnstunnel`) to
exercise a custom selection. The evidence directory gets every screenshot,
`results.json` with a PASS/FAIL per step, the server-side
`install-deploy.log` and the shared bundle zip.

## Launch screen

The native splash (Android `launch_background` and the Android 12+ system
splash icon, iOS `LaunchScreen.storyboard`) shows the MoaV lockup on the
`#0a0a0f` background. The images are rendered from `assets/icon/icon-foreground.png`
and the bundled Inter fonts by `tool/splash_assets.py`, which mirrors the
Flutter `MoavLockup` widget so the first frame lands on the splash without a
shift. After changing the mark, the wordmark or the lockup sizes:

```
python3 tool/splash_assets.py        # needs Pillow
flutter test test/launch_screen_test.dart
```

## Build artifacts

### Android

```
flutter build apk --release         # sideloadable APK
flutter build appbundle --release   # Play Store AAB
```

Release signing reads a git-ignored `android/key.properties`. When that file
is absent (CI without secrets, fresh clones) the release build type falls back
to debug signing so local builds still succeed.

The project uses Play App Signing: Google holds the app-signing key, the team
holds only the upload key. The keystore must be PKCS12, and its store and key
passwords must be identical (PKCS12 has no per-entry passwords).

Create an upload keystore once, outside the repo:

```
keytool -genkeypair -v -keystore <path>/moav-deploy-upload.jks \
  -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then add `android/key.properties`:

```
storePassword=<password>
keyPassword=<same password>
keyAlias=upload
storeFile=<path>/moav-deploy-upload.jks
```

Verify a built artifact with:

```
jarsigner -verify build/app/outputs/bundle/release/app-release.aab
```

CI reconstructs the same file from repository secrets; see
[RELEASING.md](RELEASING.md).

### iOS

```
flutter build ipa --release --export-method app-store   # TestFlight / App Store
flutter build ipa --release --export-method ad-hoc      # registered devices
```

Signing uses Xcode automatic signing. Set `DEVELOPMENT_TEAM` once in Xcode
(Runner target, Signing & Capabilities). No capabilities beyond the defaults
are required. `NSFaceIDUsageDescription` is already in `Info.plist`.
Store builds are signed with the shared distribution certificate from
fastlane match instead; see the iOS section of [RELEASING.md](RELEASING.md#ios).

## Versioning

`version: X.Y.Z+N` in `pubspec.yaml` drives both platforms. Bump `N` (the
build number) on every store upload and `X.Y.Z` per release. The release
flow is in [RELEASING.md](RELEASING.md).

## Server-side requirements

- SSH reachable (default port 22) with either the app's ed25519 key in
  `authorized_keys` or password auth for the one-time key install.
- MoaV 2.2.x. Older versions may print different `user list` and `status`
  text; the parsers in `lib/core/moav_cli.dart` are verified against 2.2.2.
- For monitoring: the `monitoring` profile running (Grafana on
  `PORT_GRAFANA`, default 9444). Headline metrics are read from Prometheus via
  `docker exec`, so the SSH user must be able to run `docker` (root).

## Secrets hygiene

- Private keys live only in the platform secure store. The app never writes
  them anywhere else and never sends them anywhere but the SSH handshake.
- Nothing in the repo contains server credentials. Live-test keys are read
  from `MOAV_TEST_SSH_KEY` at runtime.
- Fixtures under `test/fixtures/` are sanitized captures using example
  hostnames and RFC 5737 addresses.
