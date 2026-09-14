# Architecture

## Guiding principle: swap the transport, keep the app

Every server operation the UI performs is expressed once, as a method on a
`MoavController` interface. The UI, state management, and models never know
whether the work happened over SSH or over an HTTP API.

```
UI (Flutter widgets)
  → Riverpod providers / controllers (app state)
    → MoavController  (abstract interface)  ← the seam
        ├── SshMoavController   (Phase 1: drives `moav` CLI over SSH)
        └── ApiMoavController   (Phase 2: MoaV control API over HTTPS)
```

P1 invests only in `SshMoavController` and the parsing behind it. Because the
seam is the interface, P2 is additive: implement `ApiMoavController`, flip a
factory, delete nothing in the UI. **This is why we accept SSH now without it
being throwaway** — the throwaway surface is one class.

## MoavController interface (initial shape)

```dart
abstract class MoavController {
  Future<ConnectionCheck> ping();                 // reachable + moav present?
  Future<InstallHandle> install(InstallSpec spec); // detached; returns a job id
  Future<InstallStatus> installStatus(InstallHandle h);
  Future<DoctorReport> doctor();                   // per-check health
  Future<List<MoavUser>> listUsers();
  Future<MoavUser> addUser(String name);
  Future<void> removeUser(String name);
  Future<Bundle> getBundle(String user);           // configs + QR payloads
  Future<TestMatrix> testUser(String name);        // per-protocol pass/fail
  Future<void> service(ServiceAction a);           // start/stop/restart/regenerate-users
  Future<Monitoring> monitoring();                 // Grafana URL + key metrics
}
```

## Phase 1 — SSH implementation notes

- **SSH lib:** `dartssh2` (pure Dart, SSH + SFTP, ed25519).
- **CLI is the API for now.** Prefer machine-readable output. Where `moav`
  offers JSON (`-j`/`--json`), parse that; where it does not, parse text
  defensively and **file an upstream issue on MoaV** to add JSON + a
  non-interactive install. Track the gaps in `docs/MOAV-CLI-GAPS.md`.
- **Long installs survive backgrounding.** Never hold one live SSH session for
  a multi-minute install. The app uploads a small idempotent job to
  `~/.moav-deploy/` on the server (script + mode-0600 spec, written over
  stdin so secrets never hit `ps`), launches it with `setsid nohup … &`,
  returns the PID as a job handle (persisted in the secure store), and polls
  `installStatus` by tailing `~/.moav-deploy/deploy.log` on reconnect. The
  log carries `[moav-deploy] step N/5` and `[moav-deploy] exit=<code>`
  markers so status is derivable from the log alone. iOS will suspend the
  app; the server keeps working; we re-attach.
- **Install is idempotent and never destructive.** On a box that already has
  `/opt/moav` the job keeps the checkout untouched (no `git pull`), fills only
  empty/placeholder `.env` values, skips `moav bootstrap` when the box was
  already bootstrapped, and leaves running services alone. Verified live
  against yorkschool.xyz (git HEAD, `.env`, users, bundles and container set
  identical before/after).
- **Interactive installer:** `install.sh` has no `--yes`, but every prompt
  falls back to a sane default when `/dev/tty` cannot be opened (which is the
  case under `setsid`). Domain / email / admin password are not installer
  inputs at all; they live in `/opt/moav/.env`, which the job writes before
  running `moav bootstrap --yes`. Remaining gaps are in
  `docs/MOAV-CLI-GAPS.md`.

## Security

- Keys generated on-device (ed25519), stored in iOS Keychain/Secure Enclave and
  Android Keystore. Passphrase never persisted in plaintext.
- App lock: biometric / device passcode gate on launch and resume.
- "Install my public key" helper flow; support password auth as fallback only.
- No analytics, no crash-reporting phone-home by default (at-risk users).
- Assume device seizure: offer a quick wipe of stored servers/keys.

## Monitoring

MoaV already ships Grafana + Prometheus. P1: surface the Grafana URL and a few
headline numbers from `moav doctor` / the metrics endpoint; embed a Grafana
panel via webview where practical. P2: richer native charts from the API.

## Distribution

App Store + Play, plus a sideloadable APK / TestFlight path, because users in
censored regions frequently cannot reach the official stores.
