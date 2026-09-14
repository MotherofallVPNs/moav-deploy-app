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
M0–M2 done (scaffold, connect & credentials, detached idempotent deploy). Test server: `yorkschool.xyz`.

## Development
```
flutter pub get
flutter analyze --fatal-infos
flutter test                                   # unit + widget tests
MOAV_TEST_SSH_KEY=~/.ssh/key MOAV_TEST_HOST=h MOAV_TEST_USER=root flutter test test/live   # live, additive-only checks
```
