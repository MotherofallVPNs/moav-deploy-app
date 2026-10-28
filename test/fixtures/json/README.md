# `--json` fixtures

Captured verbatim from MoaV v2.3.1 (`moav.sh` plus `lib/` from upstream
`MotherofallVPNs/MoaV`) in the scratch install that upstream's own
`tests/cli-json-test.sh` builds: fake `docker compose ps` rows, fixture
configs with planted secrets, and stub `user-add.sh` / `user-revoke.sh`.
`doctor_json_rejected_2_2.txt` is what MoaV 2.2.x prints for
`moav doctor --json` (the flag is taken for a check name).

Hand-written edge cases next to the captures: `status_truncated.txt` (a
document cut off mid-row, as a dropped session yields), `status_noisy.txt`
(compose warnings and a coloured info line before the document) and
`user_list_odd.json` (entries with missing, empty or wrongly typed fields).
