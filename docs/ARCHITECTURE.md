# Architecture

## Guiding principle: swap the transport, keep the app

Every server operation the UI performs is expressed once, as a method on the
`MoavController` interface. The UI, state management and models never know
whether the work happened over SSH or over an HTTP API.

```
UI (Flutter widgets)
  -> Riverpod providers / controllers (app state)
    -> MoavController  (abstract interface)  <- the seam
        |-- SshMoavController   (today: drives the `moav` CLI over SSH)
        '-- ApiMoavController   (planned: MoaV control API over HTTPS)
```

Only `SshMoavController` and the parsing behind it exist today. Because the
seam is the interface, the API transport is additive: implement it, flip the
factory, delete nothing in the UI. The throwaway surface is one class.

## The controller interface

```dart
abstract class MoavController {
  Future<ConnectionCheck> ping();                  // reachable, moav present?
  Future<InstallHandle> install(InstallSpec spec); // detached; returns a job id
  Future<InstallStatus> installStatus(InstallHandle h);
  Future<DoctorReport> doctor();                   // per-check health
  Future<List<MoavUser>> listUsers();
  Future<MoavUser> addUser(String name);
  Future<void> removeUser(String name);
  Future<Bundle> getBundle(String user);           // configs and QR payloads
  Future<void> service(ServiceAction a, {OutputSink? onOutput}); // start/stop/restart/regenerate-users, streamed
  Future<ServiceStatusReport> status();            // moav status table and dashboard URLs
  Future<ServiceFlags> serviceFlags();             // ENABLE_* and DEFAULT_PROFILES from .env
  Future<Monitoring> monitoring();                 // Grafana health and dashboard URLs (fast)
  Future<MetricsSnapshot> metrics();               // Prometheus headline metrics (slow, own timeout)
  Future<ServerInfo> serverInfo();                 // host CPU/RAM/disk + moav and component versions
  Future<UpdateCheck> checkForUpdates();           // moav doctor updates
  Future<void> startUpdate();                      // detached moav update job
  Future<InstallStatus?> updateStatus();           // progress of that job
  Future<AdminPanelAccess> adminPanelAccess();     // PORT_ADMIN + ADMIN_PASSWORD from .env (memory only)
  Future<ServerTunnel> openTunnel(int remotePort); // ssh -L for server-local web UIs
  Future<GrafanaAccess> grafanaAccess();           // PORT_GRAFANA + ADMIN_PASSWORD from .env (memory only)
  Future<ChartsSnapshot> metricSeries();           // Prometheus range queries for the native charts
}
```

Screens that read the server (Services, Health, Analytics, Server) go through
`CachedFetchNotifier` in `lib/features/operate/operate_provider.dart`: one
non-autoDispose notifier per server and data kind that keeps the last good
value, exposes `loading`/`error` next to it, and coalesces refreshes. A tab
therefore renders cached data at once, refreshes in the background when the
cache is older than two minutes, and never blocks on a spinner after the
first load.

The concrete models live in `lib/core/moav_controller.dart`.

## SSH implementation

- **SSH library:** `dartssh2` (pure Dart, SSH and SFTP, ed25519).
- **The CLI is the API for now.** Where `moav` offers JSON (`test --json`)
  the app parses it; where it does not, the app parses text defensively. Each
  gap is recorded in [MOAV-CLI-GAPS.md](MOAV-CLI-GAPS.md) so it can be raised
  upstream.
- **Long installs survive backgrounding.** The app never holds one live SSH
  session for a multi-minute install. It uploads a small idempotent job to
  `~/.moav-deploy/` on the server (script plus a mode-0600 spec, written over
  stdin so secrets never appear in `ps`), launches it with `setsid nohup`,
  stores the PID as a job handle in the secure store, and polls
  `installStatus` by tailing `~/.moav-deploy/deploy.log` on reconnect. The
  log carries `[moav-deploy] step N/4` and `[moav-deploy] exit=<code>`
  markers so status is derivable from the log alone. The phone can suspend
  the app; the server keeps working; the app reattaches. The four steps
  (preflight, installer, bootstrap, start) have very different typical
  durations, so `InstallProgress` gives each a share of the bar and eases
  through it with the time spent in the step; 100% is the `exit=0` marker.
- **Install is idempotent and never destructive.** On a box that already has
  `/opt/moav` the installer keeps the checkout untouched (a non-interactive
  run never updates it), fills only empty or placeholder `.env` values, and
  the job asks for a bootstrap only when the box was never bootstrapped, so
  running services are left alone. The live suite re-runs the installer
  against an installed server and checks that git HEAD, `.env`, users,
  bundles and the container set are identical before and after.
- **The job drives the upstream installer's own automation contract.**
  `deploy.sh` exports `MOAV_NONINTERACTIVE=1`, `MOAV_DOMAIN` plus
  `MOAV_EMAIL` (or `MOAV_DOMAINLESS=1` when the domain is blank),
  `MOAV_ADMIN_PASSWORD`, the `ENABLE_*` flags for the services picked in the
  app (only when no `.env` exists yet, so an existing box keeps its flags),
  then pipes `install.sh` to bash inside a subshell. The installer creates
  `.env` (mode 0600), disables the certificate-dependent protocols itself in
  domainless mode, and derives `DEFAULT_PROFILES` with the repo's own
  `derive_enabled_profiles`. `moav bootstrap --yes` + `moav start` then run in
  a clean environment (steps 3 and 4), so bootstrap reads the services from `.env`
  instead of the exported `ENABLE_*` (which would otherwise re-enable the
  cert protocols domainless mode just disabled). The app writes nothing into
  `.env` itself. `deploy.sh` runs under `umask 022` (the launcher keeps its own
  files at 077) because unprivileged containers such as xray and admin read
  the clone. The catalog of profiles and flags is
  `lib/core/moav_services.dart`, mirrored from upstream `lib/service.sh`.
- **Parsing.** Command strings and parsers live in `lib/core/moav_cli.dart`,
  separate from the transport, with fixture-based unit tests. `user list`,
  `doctor` and `status` are text-parsed; `test` uses `--json`, found as the
  trailing JSON document after Docker build noise. Bundles are read over SFTP
  from `/opt/moav/outputs/bundles/<user>`; only text configs are pulled, and
  single-line links or WireGuard confs become QR payloads. Usernames are
  validated on-device with the CLI's own rule before they are shell-quoted,
  and `user revoke` is confirmed by re-listing since the CLI always exits 0
  for it. Prometheus is not published on the host, so headline metrics go
  through `docker exec moav-prometheus wget` against the port parsed from
  the container's `--web.listen-address`.

## Security

- Keys are generated on-device (ed25519) and stored in the iOS Keychain or
  Android Keystore through `flutter_secure_storage`. Passphrases are never
  persisted in plaintext.
- App lock: biometric or device passcode gate on launch and resume.
- "Install my key" helper flow; password auth is a fallback for that one
  step only.
- No analytics and no crash reporting. Errors are scrubbed by
  `lib/security/redactor.dart` before they reach any log or notice.
- Device seizure is assumed: the emergency wipe clears every stored server,
  key and install handle.

## Monitoring

MoaV ships Grafana and Prometheus. The app derives the Grafana URL the same
way the CLI does from `.env`, probes `/api/health` for up and version, reads
seven headline numbers from Prometheus instant queries, and embeds Grafana in
a webview with open-in-browser for self-signed certificates. Native charts
are a candidate for the API transport.

## Design system

The app is dark-only and shares MoaV's visual language with the website.
`lib/theme/moav_theme.dart` is the single source of tokens: backgrounds
`#0a0a0f`, `#12121a`, `#15151f`; text ramp from white through `#a0a0b0` to
`#606070`; cyan `#00d4ff` to purple `#7b5cff` accent gradient; 12 and 8 px
radii. Inter is the UI face; JetBrains Mono is used for anything that is a
value: hosts, keys, metrics, service names, logs. Both are bundled under
`assets/fonts`, so no font is ever fetched at runtime. Screens only compose
the theme's widgets (`MoavScaffold`, `MoavCard`, `SectionHeader`,
`MetricTile`, `StatusPill`, `GradientButton`, `CodeBlock`).

The Analytics tab (`lib/features/operate/analytics_view.dart`) turns the flat
headline metric list into tiles, derives per-protocol status from the
`moav status` service table, and embeds Grafana inline through the same
`GrafanaPanel` the full-screen view uses.

## Distribution

Google Play and GitHub Releases today, App Store and TestFlight next, because
users in censored regions frequently cannot reach the official stores. See
[DISTRIBUTION.md](DISTRIBUTION.md).
