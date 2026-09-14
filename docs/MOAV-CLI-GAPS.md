# MoaV CLI gaps blocking robust automation

Tracking where the `moav` CLI forces text-scraping or interactive input, so we
can raise them upstream on MotherofallVPNs/moav.

| Need | Why | Status |
|---|---|---|
| JSON output on `moav user list`, `doctor`, `test` | avoid fragile text parsing | to confirm |
| Non-interactive `install.sh` (env/answers-file for domain/email/admin-pass) | app cannot reliably drive a TTY prompt in background | to confirm |
| Stable machine-readable `moav test` result codes | per-protocol pass/fail UI | to confirm |
