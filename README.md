# MoaV Deploy

A Flutter mobile app (iOS + Android) to **deploy, manage, and monitor [MoaV](https://github.com/MotherofallVPNs/moav) servers** from your phone.

- **Phase 1** — single server: connect over SSH, install MoaV, manage users, hand out bundles/QR, restart services, view health and Grafana.
- **Phase 2** — fleet: multi-server registry, cross-server user management, multi-server redundancy bundles, and a native MoaV control API replacing SSH.

## Design stance
- **Self-custody, no middleman.** The app talks directly to *your* server. No central backend ever holds your SSH keys or your users. This matches MoaV's no-telemetry ethos.
- **API-ready from day one.** All server operations go through a `MoavController` interface. P1 ships an `SshMoavController` (drives the `moav` CLI over SSH); P2 adds an `ApiMoavController` (talks to the MoaV control API) with zero UI rewrite.
- **Threat-modelled for at-risk users.** Keys in Secure Enclave / Keystore, biometric lock, nothing sensitive at rest in plaintext.

See [`docs/PLAN.md`](docs/PLAN.md) and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Status
M0–M4 done (scaffold, connect & credentials, detached idempotent deploy, users + bundles/QR, operate & monitor). M5 (harden & ship) next. Test server: `yorkschool.xyz`.

More docs: [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md), [`docs/APP-STORES.md`](docs/APP-STORES.md), [`docs/WORKFLOW.md`](docs/WORKFLOW.md), [`docs/MOAV-CLI-GAPS.md`](docs/MOAV-CLI-GAPS.md).

## Development
```
flutter pub get
flutter analyze --fatal-infos
flutter test                                   # unit + widget tests
MOAV_TEST_SSH_KEY=~/.ssh/key MOAV_TEST_HOST=h MOAV_TEST_USER=root flutter test test/live   # live, additive-only checks
```

### Design system
`lib/theme/moav_theme.dart` holds the MoaV tokens (same values as the site's
`blog.css`: `#0a0a0f` backgrounds, cyan `#00d4ff` → purple `#7b5cff` accent,
Inter + JetBrains Mono) as a dark-only Material 3 `ThemeData`, plus the
reusable pieces every screen is built from: `MoavScaffold` (radial glow),
`MoavCard`, `SectionHeader`, `MetricTile`, `StatusPill`, `GradientButton`,
`CodeBlock`. Fonts are bundled from `assets/fonts` — nothing is fetched at
runtime.

### Screenshot gallery
`tool/screenshots.sh` drives the app on a booted iOS simulator with
`integration_test` and writes PNGs to `shots/` (git-ignored; the curated set
lives in [`docs/screenshots/`](docs/screenshots/)). By default it uses
yorkschool-shaped fake data; with the `MOAV_TEST_*` variables above it talks
to the real box, read-only except for one throwaway `zzmoavdeploytest*` user
that is created for the bundle/QR shot and revoked afterwards.
