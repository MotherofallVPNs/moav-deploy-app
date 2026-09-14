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
  a multi-minute install. Launch it detached on the server
  (`nohup … > /opt/moav/.deploy.log 2>&1 &` or a tmux session), return a job
  handle, and poll `installStatus` by tailing that log on reconnect. iOS will
  suspend the app; the server keeps working; we re-attach.
- **Interactive installer:** `install.sh` prompts for domain / email / admin
  password. Drive it non-interactively via env/answers file if MoaV supports
  it; otherwise feed answers over the PTY as a stopgap and push the
  env-driven install upstream.

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
