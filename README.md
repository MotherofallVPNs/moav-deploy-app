<div align="center">

<img src="assets/icon/icon-1024.png" alt="MoaV Deploy logo" width="130">

# MoaV Deploy

**Install, manage and monitor your own [MoaV](https://github.com/MotherofallVPNs/MoaV) server from your phone.**

[![CI](https://img.shields.io/github/actions/workflow/status/MotherofallVPNs/moav-deploy-app/ci.yml?branch=main&label=CI&logo=github&logoColor=white)](https://github.com/MotherofallVPNs/moav-deploy-app/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/MotherofallVPNs/moav-deploy-app?label=release&color=16a34a&logo=github&logoColor=white)](https://github.com/MotherofallVPNs/moav-deploy-app/releases/latest) [![Flutter](https://img.shields.io/badge/Flutter-3.32%2B-02569B.svg?logo=flutter&logoColor=white)](https://flutter.dev) [![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS-0ea5e9.svg)](#get-the-app) [![License: MIT](https://img.shields.io/badge/license-MIT-22c55e.svg)](LICENSE)

[![Website](https://img.shields.io/badge/website-moav.sh-06b6d4.svg)](https://moav.sh) [![Docs](https://img.shields.io/badge/docs-moav.sh%2Fdocs-2563eb.svg)](https://moav.sh/docs/) [![MoaV](https://img.shields.io/badge/server-MoaV-8b5cf6.svg?logo=github&logoColor=white)](https://github.com/MotherofallVPNs/MoaV) [![moav-client](https://img.shields.io/badge/client-moav--client-7c3aed.svg?logo=github&logoColor=white)](https://github.com/MotherofallVPNs/moav-client) [![Telegram](https://img.shields.io/badge/Telegram-motherofallvpns-2CA5E0.svg?logo=telegram)](https://t.me/motherofallvpns) [![X](https://img.shields.io/badge/X-@motherofallvpns-000000.svg?logo=x)](https://x.com/motherofallvpns)

<a href="https://play.google.com/store/apps/details?id=org.motherofallvpns.moavdeploy"><img src="https://img.shields.io/badge/Google_Play-open_testing-34A853.svg?style=for-the-badge&logo=googleplay&logoColor=white" alt="Get it on Google Play" height="36"></a>&nbsp;&nbsp;<img src="https://img.shields.io/badge/App_Store-coming_soon-6b7280.svg?style=for-the-badge&logo=apple&logoColor=white" alt="App Store: coming soon" height="36">

Built and maintained by the **[MoaV](https://github.com/MotherofallVPNs)** community.

</div>

---

## What it is

MoaV Deploy is a Flutter app for Android and iOS that turns a plain VPS into a
running [MoaV](https://github.com/MotherofallVPNs/MoaV) server and then keeps it
running. It connects to your server over SSH, drives the `moav` CLI, and gives
you a phone-sized control panel for the things you do every week: add a user,
hand out a bundle as a QR code, restart a service, check health, glance at
Grafana.

It is a **server administration** app, not a VPN client. It never routes your
phone's traffic. To connect to a MoaV server, use any compatible client with
the bundles this app produces.

## Features

- **Deploy** MoaV onto a fresh server with a guided, resumable install. The
  install job runs detached on the server, so the app can be backgrounded or
  closed and will reattach to the running job.
- **Users and bundles.** Add and revoke users, pull a user's bundle over SFTP,
  and show every phone link (Reality, Hysteria2, Trojan, Shadowsocks, XHTTP,
  WireGuard, AmneziaWG, MTProxy) as a QR code with copy and share.
- **Operate.** Start, stop and restart services, run `moav doctor`, read the
  live service table, and open the admin dashboard inside the app.
- **Monitor.** Headline metrics from Prometheus and Grafana embedded in the
  app, with an open-in-browser fallback for self-signed certificates.
- **Donate.** See what the server gives back (Psiphon Conduit and Tor
  Snowflake bandwidth, configs donated to MahsaNet), save the MahsaNet API key
  to the server once, and generate and donate a batch of configs with one
  confirmed tap. Money donations live in the "Support us" popup.
- **Keys and servers.** On-device ed25519 key generation, a reusable keyring,
  one-time password login to install your key, and multiple server profiles.
- **Built for at-risk users.** Biometric app lock, secrets only in the
  platform secure store, scrubbed logs, no telemetry, no backend, and an
  emergency wipe that clears every stored server and key.
- **Disguise mode.** The app can present itself as a plain Notes app (name
  and icon on Android, icon on iOS) with a working notes screen in front; a
  secret gesture plus a per-device passcode reveals the real app behind its
  usual lock. See [docs/DISGUISE.md](docs/DISGUISE.md).

## Get the app

| Channel | Status |
|---|---|
| [Google Play](https://play.google.com/store/apps/details?id=org.motherofallvpns.moavdeploy) | Open testing |
| [GitHub Releases](https://github.com/MotherofallVPNs/moav-deploy-app/releases) | Signed APK and AAB attached to every release |
| App Store | Not yet published |

You need your own server with SSH access. MoaV itself is free and open source;
see the [MoaV docs](https://moav.sh/docs/) for server requirements.

### Verify a sideloaded APK

Every release carries a `SHA256SUMS` file written by the same CI run that
built the APK. Download it next to `app-release.apk` and run:

```sh
sha256sum --ignore-missing -c SHA256SUMS   # macOS: shasum -a 256 --ignore-missing -c SHA256SUMS
```

Install only if it prints `app-release.apk: OK`. Once installed, the menu's
**About** screen shows the SHA-256 fingerprint of the certificate that signed
the running build, read from Android at runtime. Official GitHub APKs all share
one fingerprint, so it must not change between updates; a different value means
the APK was re-signed by someone else. The published fingerprint is:

```
SHA-256: BB:D5:65:A1:38:FE:28:83:16:73:F7:86:59:EC:A2:C3:13:9D:6B:86:21:16:C8:A1:B8:BB:9D:71:96:F8:0A:A6
```

This is the upload key that signs the APK and AAB attached to each GitHub
release. Play Store installs show Google's own re-signing certificate instead,
because Play App Signing re-signs every build Google distributes.

## How it works

Every server operation goes through one `MoavController` interface. Today the
only implementation drives the `moav` CLI over SSH (`SshMoavController`); a
future implementation can talk to a native MoaV control API without touching
the UI. The design, the install job, and the parsing strategy are described in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Places where the CLI still forces
text scraping are tracked in [docs/MOAV-CLI-GAPS.md](docs/MOAV-CLI-GAPS.md).

## Development

Requirements: Flutter 3.32 or newer on the stable channel, Xcode for iOS,
Android SDK with JDK 17 for Android. Full setup, signing and live-test details
are in [docs/BUILDING.md](docs/BUILDING.md).

```
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter run -d <device>
```

Tests tagged `live` under `test/live/` talk to a real MoaV server and are
skipped unless the `MOAV_TEST_*` variables are set. They are additive only and
run in CI solely through the secrets-gated live workflow described in
[docs/LIVE-CI.md](docs/LIVE-CI.md).

```
MOAV_TEST_SSH_KEY=~/.ssh/key MOAV_TEST_HOST=your.server MOAV_TEST_USER=root flutter test test/live
```

### Repository layout

```
lib/
  core/        MoavController interface, SSH transport, CLI parsers, install job
  features/    One folder per screen group: servers, keys, deploy, users, operate, wipe, about
  security/    App lock, onboarding, secure store, key services, redaction, wipe
  theme/       MoaV design tokens and the shared widget set
test/          Unit and widget tests; test/live/ needs a real server
integration_test/, test_driver/, tool/screenshots.sh
               Screenshot gallery harness for a booted iOS simulator
android/, ios/ Platform projects; android/fastlane holds the Play lanes
fastlane/metadata/android/
               Store listing text and release notes (source of truth)
scripts/       Release helpers used by CI
docs/          Architecture, building, releasing, distribution, CLI gaps
.github/       CI and release workflows, PR template
```

### Design system

`lib/theme/moav_theme.dart` holds the MoaV tokens (dark backgrounds, cyan to
purple accent, Inter for UI, JetBrains Mono for values) as a dark-only Material
3 theme plus the widgets every screen is composed from. Fonts are bundled under
`assets/fonts`; nothing is fetched at runtime.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): the controller seam, the
  detached install job, parsing, security model.
- [docs/BUILDING.md](docs/BUILDING.md): toolchain, running locally, signing,
  live tests, server-side requirements.
- [docs/RELEASING.md](docs/RELEASING.md): version bump, release notes, GitHub
  Release, Play delivery, required secrets.
- [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md): store, sideload and TestFlight
  channels and what each one needs.
- [docs/MOAV-CLI-GAPS.md](docs/MOAV-CLI-GAPS.md): upstream CLI gaps the app
  works around.
- [docs/DISGUISE.md](docs/DISGUISE.md): disguise mode (Notes decoy), its
  threat model and what each platform can and cannot hide.

## Contributing

Pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for the
branch and PR conventions, and the rules for the live test suite. Security
issues go through [SECURITY.md](SECURITY.md), not the public tracker.

## Roadmap

Phase 1 (single server over SSH) has shipped. Phase 2 is a fleet view across
several servers backed by a native MoaV control API; it is tracked in
[issue #7](https://github.com/MotherofallVPNs/moav-deploy-app/issues/7).

## Related projects

- [MoaV](https://github.com/MotherofallVPNs/MoaV): the server stack this app manages.
- [moav-client](https://github.com/MotherofallVPNs/moav-client): the client side.

## License

MoaV Deploy is released under the [MIT License](LICENSE). The bundled Inter
and JetBrains Mono fonts are under the SIL Open Font License; their license
texts ship inside the app through Flutter's license registry.
