# Implementation Plan

Test server for every milestone: **yorkschool.xyz**. Definition of done for P1:
the app installs and manages MoaV on yorkschool.xyz and shows its Grafana.

## Phase 1 — single server (the milestone)

### M0. Project scaffold
- Flutter app (iOS + Android), Riverpod state, `flutter_secure_storage`, `dartssh2`, `qr_flutter`, `webview_flutter`.
- CI: `flutter analyze` + `flutter test` on push (GitHub Actions).
- `MoavController` interface + `SshMoavController` skeleton (methods throwing `UnimplementedError`). ✅

### M1. Connect & credentials ✅
- Add-server form: host, port, username, auth (generate/import ed25519 key **or** password).
- Store creds in Secure Enclave / Keystore; biometric app-lock.
- "Install my public key" helper (one-time password, verified by a key-auth session). `ping()`: opens an SSH session, runs `moav --version`.

### M2. Deploy ✅
- `install(InstallSpec)`: run `install.sh` **detached**, return a job handle.
- `installStatus`: tail the deploy log, render live progress; survive app suspend/reconnect.
- Domain/email/admin-password are written to `.env` (only when unset) before `moav bootstrap --yes`; no PTY driving needed.

### M3. Manage users
- List / add / remove users (`moav user …`).
- `getBundle`: pull a user's bundle over SFTP, render QR + share sheet.
- `testUser`: run `moav test <user>`, show per-protocol pass/fail/warn.

### M4. Operate & monitor
- Service controls: start / stop / restart / `regenerate-users`.
- `doctor()` health view (green/red per check).
- Grafana: surface URL + headline metrics; embed a panel via webview.

### M5. Harden & ship P1
- Error states, offline/timeout handling, redaction (never log secrets).
- Device-seizure quick-wipe.
- TestFlight + internal APK.

## Phase 2 — fleet & API
- **MoaV control API** (`ApiMoavController`) — server-side daemon; the real fix for CLI scraping. Coordinate the API contract with the MoaV repo.
- Multi-server registry + fleet health dashboard.
- Cross-server user management.
- **Multi-server redundancy bundles** — one user, configs spanning several servers (directly MoaV's "no single block cuts you off" story).

## Cross-cutting upstream dependency
`moav` CLI needs **JSON output** and a **non-interactive install** to make the
app robust. Tracked in `docs/MOAV-CLI-GAPS.md`; raise as issues/PRs on
`MotherofallVPNs/moav`. This is on the critical path for a non-fragile P1.

## Open decisions
- Grafana in-app: embedded webview vs native charts (start embedded).
- API auth model for P2 (token vs mTLS) — decide with the MoaV API design.
