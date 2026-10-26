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

The app still uses the text parsers below because they work on every 2.2.x
box in the field. Moving to `--json` when the server reports 2.3.0 or newer
is a follow-up: detect the version from `moav --version`, prefer JSON, and
keep the text path as the fallback.

### Still missing upstream

| Need | Why | Status in 2.3.1 |
|---|---|---|
| `moav --version` machine-readable | detect the installed version before choosing a parser | still ANSI-coloured text (`MoaV v2.3.1`); the app parses it with a regex |
| Prometheus reachable from the host, or a `moav metrics` command | headline metrics | still not published on the host; the app uses `docker exec moav-prometheus wget` with the port parsed from `--web.listen-address` |
| `moav user revoke` exit code on the text path | detect failure without `--json` | `--json` exits non-zero on an unknown user; the text path still exits 0 |
| `moav regenerate-users` / `moav start|stop|restart` result | service actions and bundle refresh | plain text, no `--json`; the app relies on the exit code and re-reads `moav status` afterwards |

## JSON shapes the app will consume (MoaV 2.3.x)

- `moav status --json`: `{version, admin_url, grafana_url, admin_port,
  grafana_port, default_profiles: [...], services: [{name, state, uptime,
  ports: [...]}]}`. `state` is one of `running`, `unhealthy`, `starting`,
  `never` or the raw compose state. URLs are `null` unless domain-based.
- `moav doctor [check] --json`: `[{id, status: pass|warn|fail, detail}]`,
  details colour-stripped and redacted.
- `moav user list --json`: `[{user, services: [...], bundle: bool}]`.
- `moav user add|remove NAME --json`: `{ok, action, users: [...]}` or
  `{ok: false, action, error}`.
- `moav test USER --json`: `{overall_status, summary, tests: {proto: {status,
  detail}}}`, unchanged from 2.2.x.

## What the text parsers rely on (MoaV 2.2.x)

| Need | Why | How the app copes |
|---|---|---|
| JSON output on `moav user list`, `doctor`, `status` | avoid fragile text parsing; `status` is a box-drawn table with ANSI colour | text parsers, see rows below |
| Non-interactive `install.sh` | app drives it in the background | every `confirm` reads `/dev/tty` and falls back to its default when that fails (e.g. under `setsid`). Defaults: install packages = yes, update existing checkout = **no** (good: never touches a live box), install global command = yes, swap/net-tuning = yes (skipped if already applied). Domain/email/admin password are `.env` keys, not installer inputs. |
| `install.sh`: "Start Docker now?" defaulted to **no** | on a fresh box where Docker was just installed but not started, a non-interactive run continued without Docker | fixed in 2.3.0 for non-interactive runs (defaults to yes). On a 2.2.x installer the app's install job inherits the old default and does not check Docker separately. |
| `moav bootstrap --yes` | idempotent re-run; preserves keys/users, regenerates configs | exists in 2.2.x; on 2.2.x it still entered interactive service selection afterwards (fixed in 2.3.0) |
| Env-driven config (`DOMAIN`, `ACME_EMAIL`, `ADMIN_PASSWORD`) | app fills them before bootstrap | plain `KEY="value"` lines in `/opt/moav/.env` (template `.env.example`). The app only fills empty/placeholder values so an existing box is never reconfigured silently. |
| Stable machine-readable `moav test` result codes | per-protocol pass/fail UI | `moav test USER --json` exists on 2.2.x. On 2.2.x the JSON is the *tail* of stdout after `docker build` chatter, so the app scans backwards for the last decodable `{…}`; harmless on 2.3.x where stdout is clean. |
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
4. `moav bootstrap --yes` **only** if `outputs/bundles` is empty (never bootstrapped).
5. `moav start` only if step 4 ran; otherwise print `moav status` and leave services alone.

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
