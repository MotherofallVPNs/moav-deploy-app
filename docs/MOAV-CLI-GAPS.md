# MoaV CLI gaps blocking robust automation

Tracking where the `moav` CLI forces text-scraping or interactive input, so we
can raise them upstream on MotherofallVPNs/moav. Findings below were verified
against MoaV **v2.2.2** on yorkschool.xyz (2026-09-14).

| Need | Why | Status |
|---|---|---|
| JSON output on `moav user list`, `doctor`, `test`, `status` | avoid fragile text parsing; `status` is a box-drawn table with ANSI colour | **confirmed gap** — no `--json`/`-j` anywhere in `moav --help` |
| Non-interactive `install.sh` | app drives it in the background | **workable without changes**: no `--yes` flag, but every `confirm` reads `/dev/tty` and falls back to its default when that fails (e.g. under `setsid`). Defaults: install packages = yes, update existing checkout = **no** (good: never touches a live box), install global command = yes, swap/net-tuning = yes (skipped if already applied). Domain/email/admin password are **not** installer inputs; they are `.env` keys. |
| `install.sh`: "Start Docker now?" defaults to **no** | on a fresh box where Docker was just installed but not started, a non-interactive run continues without Docker | to raise upstream: default to yes when non-interactive, or honour `MOAV_YES=1` |
| `moav bootstrap --yes` | idempotent re-run; preserves keys/users, regenerates configs | **exists**. Note: after bootstrap it still enters interactive *service selection* (`select_profiles`) and a "Start services now?" prompt; non-TTY behaviour of `select_profiles` is unverified for fresh installs. To raise upstream: `--yes` should also accept the saved/default profiles. |
| Env-driven config (`DOMAIN`, `ACME_EMAIL`, `ADMIN_PASSWORD`) | app fills them before bootstrap | **workable**: plain `KEY="value"` lines in `/opt/moav/.env` (template `.env.example`). The app only fills empty/placeholder values so an existing box is never reconfigured silently. |
| Stable machine-readable `moav test` result codes | per-protocol pass/fail UI | to confirm (M3) |
| `moav --version` output | detect installed version | text with ANSI colour: `MoaV v2.2.2`; parsed with a regex. A `--version --plain` or JSON would be nicer. |

## How the app installs today (M2)

`~/.moav-deploy/deploy.sh` on the server (see `lib/core/install_script.dart`):

1. Preflight: report whether `/opt/moav` exists; it is never removed or updated.
2. `curl -fsSL https://moav.sh/install.sh | bash` with no TTY (see defaults above).
3. Ensure `.env` exists; fill only empty/placeholder `DOMAIN`, `ACME_EMAIL`, `ADMIN_PASSWORD`.
4. `moav bootstrap --yes` **only** if `outputs/bundles` is empty (never bootstrapped).
5. `moav start` only if step 4 ran; otherwise print `moav status` and leave services alone.
