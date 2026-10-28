# MoaV CLI gaps the app works around

Where the `moav` CLI forced text scraping or interactive input, what the app
does about it, and what upstream has since shipped. The parsers in
`lib/core/moav_cli.dart` were verified against MoaV **v2.2.2** on a live
server in September 2026 and are mirrored on
[issue #8](https://github.com/MotherofallVPNs/moav-deploy-app/issues/8).

## Upstream status (checked against MoaV v2.3.1, October 2026)

MoaV **2.3.0** (2026-10-21) shipped most of what issue #8 asked for, citing
this app as the consumer:

- `--json` on `moav status`, `moav doctor [check]`, `moav user list`,
  `moav user add`, `moav user remove|revoke` and `moav test`. One document on
  stdout, logs on stderr, secret-free by construction (no keys, passwords,
  share links or server addresses).
- Non-interactive `install.sh`: `MOAV_NONINTERACTIVE=1` or
  `--non-interactive`, with `MOAV_DOMAIN`, `MOAV_EMAIL`, `MOAV_ADMIN_PASSWORD`
  and `ENABLE_*` from the environment, or `--answers FILE` (mode `0600`).
  Fails closed on a missing answer, never takes the password from argv.
  "Start Docker now?" now defaults to yes when non-interactive.
  `MOAV_BOOTSTRAP=1` opts into `moav bootstrap --yes` at the end.
- `moav bootstrap --yes` honours the saved `DEFAULT_PROFILES` instead of
  entering the interactive service selection.
- `moav test --json` keeps stdout clean (progress and image build on stderr).
- `confirm()` returns its default without touching `/dev/tty` under
  `MOAV_NONINTERACTIVE=1`.

The app now sends `--json` for `status`, `doctor`, `user list`, `user add`,
`user remove` and `test`, and parses the documents below
(`MoavCli.parse*Json`). When the output is not a JSON document the box is
treated as 2.2.x and the text parsers take over: `status` and `user list`
are parsed from the same output (2.2.x ignores the flag), while `doctor`,
`user add` and `user remove` are re-run without the flag (2.2.x rejects it
before doing anything). `SshMoavController` logs `<command> via json|text`
through `AppLog` in debug builds. The remaining text-only paths carry a
`TODO(#8)` marker in the code.

### Still missing upstream

| Need | Why | Status in 2.3.1 |
|---|---|---|
| `moav --version` machine-readable | detect the installed version before choosing a parser | still ANSI-coloured text (`MoaV v2.3.1`); the app parses it with a regex |
| Grafana settings | in-app Grafana over an SSH tunnel | `PORT_GRAFANA` (default 9444), `ENABLE_MONITORING` and `ADMIN_PASSWORD` are read from `/opt/moav/.env` (`MoavCli.grafanaPanel`), plus a loopback `/api/health` probe for https vs http. Grafana runs with `GF_SECURITY_ADMIN_USER=admin` and `GF_SECURITY_ADMIN_PASSWORD=${ADMIN_PASSWORD}` (docker-compose.yml), so the app posts that password to `POST /login` through the tunnel and installs the session cookies in the webview (`lib/core/grafana_login.dart`). Memory only; the public Grafana port is never used by the in-app view. |
| Prometheus reachable from the host, or a `moav metrics` command | headline metrics and the native charts | still not published on the host; the app uses `docker exec moav-prometheus wget` with the port parsed from `--web.listen-address`, for instant queries (`MoavCli.prometheus`) and one-hour range queries (`MoavCli.prometheusRange`, PromQL copied from the provisioned dashboards) |
| `moav user revoke` exit code on the text path | detect failure without `--json` | `--json` exits non-zero on an unknown user; the text path still exits 0 |
| User bundle contents | the bundle and QR screens | no `moav user show --json`; the app prints `outputs/bundles/<user>` in one shell round trip, each text file base64-framed (`MoavCli.bundleDump`). Replaced an SFTP walk that cost four round trips per file |
| `moav regenerate-users` / `moav start|stop|restart` result | service actions and bundle refresh | plain text, no `--json`; the app relies on the exit code and re-reads `moav status` afterwards |
| `ENABLE_*` flags readable and settable through `moav` | per-service enable/disable in the app | no `moav enable|disable` and `moav status --json` omits the flags; the app reads `.env` with `grep` and writes it like `update_env_var` (`MoavCli.serviceFlags`, `MoavCli.setEnableFlags`) |
| Host metrics (CPU, RAM, swap, disk) | the Server tab | no `moav` command; the app reads `/proc/loadavg`, `/proc/stat`, `/proc/meminfo`, `/proc/uptime` and `df -Pk /` in one marker-delimited snippet (`MoavCli.hostInfo`) |
| `moav --version` component table | the Server tab | box-drawn text; parsed by `│` columns (`MoavCli.parseVersionInfo`) |
| `moav update` without prompts | in-app self-update | `moav doctor updates --json` reports the verdict. MoaV #345 added `moav update --yes` (= `MOAV_NONINTERACTIVE=1`: stash local changes, accept pins and `.env` additions, no restart). Older `cmd_update` rejects the flag with `Unknown option: --yes` and exits 1 before touching git, so the detached job (`lib/core/update_script.dart`) runs `update --yes` first and, on that exact line, re-runs plain `moav update` with `1\nY\n` on stdin (stash, accept versions; the `.env` additions prompt takes its `[Y/n]` default on EOF). Services are never rebuilt or restarted by the app |

## JSON shapes the app consumes (MoaV 2.3.x)

Captured verbatim from v2.3.1 into `test/fixtures/json/`.

- `moav status --json`: `{version, admin_url, grafana_url, admin_port,
  grafana_port, default_profiles: [...], services: [{name, state, uptime,
  ports: [int]}]}`. `state` is one of `running`, `unhealthy`, `starting`,
  `never` or the raw compose state (`exited`, `created`, ...). URLs are
  `null` unless domain-based; `uptime` is `""` when not running. There is
  no Grafana CDN URL in the document.
- `moav doctor [check] --json`: `[{id, status: pass|warn|fail, detail}]`,
  details colour-stripped, redacted and joined with `; `. Exit code is
  non-zero when any check fails.
- `moav user list --json`: `[{user, services: [...], bundle: bool}]`; the
  MTProxy store is called `telemt` here (the app maps it to `telegram`).
- `moav user add|remove NAME --json`: `{ok, action: add|remove, users:
  [{user, ok, error?, bundle_dir?}]}` or `{ok: false, action, error}` when
  the request never reached the scripts. Exit code is non-zero when `ok`
  is false (including `already exists` on add and an unknown user on remove).
- `moav test USER --json` exists upstream but the app no longer runs it (the
  per-protocol client test was removed as slow and low value).

## What the text parsers rely on (MoaV 2.2.x)

| Need | Why | How the app copes |
|---|---|---|
| JSON output on `moav user list`, `doctor`, `status` | avoid fragile text parsing; `status` is a box-drawn table with ANSI colour | text parsers, see rows below |
| Non-interactive `install.sh` | app drives it in the background | every `confirm` reads `/dev/tty` and falls back to its default when that fails (e.g. under `setsid`). Defaults: install packages = yes, update existing checkout = **no** (good: never touches a live box), install global command = yes, swap/net-tuning = yes (skipped if already applied). Domain/email/admin password are `.env` keys, not installer inputs. |
| `install.sh`: "Start Docker now?" defaulted to **no** | on a fresh box where Docker was just installed but not started, a non-interactive run continued without Docker | fixed in 2.3.0 for non-interactive runs (defaults to yes). On a 2.2.x installer the app's install job inherits the old default and does not check Docker separately. |
| `moav bootstrap --yes` | idempotent re-run; preserves keys/users, regenerates configs | exists in 2.2.x; on 2.2.x it still entered interactive service selection afterwards (fixed in 2.3.0) |
| Env-driven config (`DOMAIN`, `ACME_EMAIL`, `ADMIN_PASSWORD`) | app fills them before bootstrap | plain `KEY="value"` lines in `/opt/moav/.env` (template `.env.example`). The app only fills empty/placeholder values so an existing box is never reconfigured silently. |
| Admin dashboard settings | in-app admin panel over an SSH tunnel | `PORT_ADMIN`, `ENABLE_ADMIN_UI` and `ADMIN_PASSWORD` are read from `/opt/moav/.env` (`MoavCli.adminPanel`). The password is held in memory only and answers the panel's HTTP Basic challenge (any username, see upstream `admin/main.py`). |
| `moav user list --json` | user list | 2.2.x: sectioned text (`=== sing-box Users … ===`, `• name [bundle ready]`, `• name (10.66.66.106)`). Parsed by section; a user is "bundle ready" when listed under `=== User Bundles ===`. |
| `moav user revoke` exit code | detect failure | `cmd_user revoke` loops `user-revoke.sh "$u" \|\| true`, so the text path exits 0 even for an unknown user. The app re-lists users afterwards to confirm. |
| `moav doctor --json` | health view | 2.2.x: text grouped by `name - description` headers with `✓ ! ○ ✗ ℹ` markers, some checks (dns) print unindented. The app derives fail/warn/pass per check from the markers. |
| `moav status --json` | services table | 2.2.x: box-drawn table; parsed by `│` columns. The URL lines (`Admin Dashboard:`, `Grafana:`, `Grafana (CDN):`) and `Default profiles:` are parsed too. |
| Bundle download | QR + share in app | `/opt/moav/outputs/bundles/<user>/` is read over SFTP (mode 0770, owner `2000`, root can read). Phone links are single-line `*.txt`; WireGuard/AmneziaWG `.conf` files are QR-able as-is. |

## How the app installs today

`~/.moav-deploy/deploy.sh` on the server (see `lib/core/install_script.dart`):

1. Preflight: report whether `/opt/moav` exists; it is never removed or updated.
2. `curl -fsSL https://moav.sh/install.sh | bash` with no TTY (see defaults above).
3. Ensure `.env` exists; fill only empty/placeholder `DOMAIN`, `ACME_EMAIL`, `ADMIN_PASSWORD`.
   Then write the services chosen in the app: `DEFAULT_PROFILES` is filled
   when empty (it is what `moav bootstrap --yes` and a bare `moav start`
   use without a TTY, see `BOOTSTRAP_ASSUME_YES` in `lib/bootstrap.sh`), and
   the matching `ENABLE_*=true|false` flags are written only to a `.env`
   this run created, so an existing box keeps its flags.
4. `moav bootstrap --yes` **only** if `outputs/bundles` is empty (never bootstrapped).
5. `moav start` only if step 4 ran; otherwise print `moav status` and leave services alone.

There is no non-interactive profile argument on `moav bootstrap` or
`moav start`; `install.sh --non-interactive` derives `DEFAULT_PROFILES` from
the `ENABLE_*` environment the same way (`ni_default_profiles`). The app's
profile list and flag table (`lib/core/moav_services.dart`) mirror
`select_profiles`, `profile_enabled` and `confirm_disabled_profile` in
upstream `lib/service.sh` (v2.3.1).

## Per-service controls

`moav start|stop|restart <service>` take a Compose service name as printed
by `moav status` (`cmd_start` resolves aliases such as `sing-box` to the
`proxy` profile, `stop`/`restart` act on the single container). A bare
`moav start <name>` on a service whose `ENABLE_*` is `false` prompts, and
without a TTY it skips and exits non-zero, which the app surfaces verbatim.
Enable/disable have no `moav` verb: the app writes the flag(s) with the
same replace/uncomment/append rules as upstream `update_env_var`
(`MoavCli.setEnableFlags`) and then runs `moav start` or `moav stop` for the
service. Flags are read back with a `grep` over `.env`
(`MoavCli.serviceFlags`); `moav status --json` does not report them.

Switching step 2 to `MOAV_NONINTERACTIVE=1` with the `MOAV_*` answers in the
environment is the natural next step once 2.3.x is the baseline; it removes
the `/dev/tty` fallback dependency and lets the installer fail closed.

## Eventual consistency of `moav user list` after add/revoke

`moav user add` / `moav user revoke` trigger an asynchronous service
regeneration. On a busy box, `moav user list` can briefly report a stale or
transient count (e.g. a just-revoked user reappearing, or an extra transient
entry) for a few seconds before settling. The app's `SshMoavController` already
re-lists to confirm add/remove, but clients must treat the user count as
eventually consistent. Live tests poll with a bounded settle window rather than
asserting on the first read. Whether `moav user list --json` on 2.3.x gives a
definitive, post-regen view is not yet verified.
