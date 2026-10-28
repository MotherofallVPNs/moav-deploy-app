#!/usr/bin/env bash
# Runs integration_test/e2e_live_test.dart against a real, disposable box
# through the app UI on an iOS simulator, then collects the evidence
# (screenshots, per-step results, install log, the shared bundle zip).
#
#   MOAV_TEST_HOST=1.2.3.4 MOAV_TEST_USER=root \
#   MOAV_TEST_PASSWORD='ssh password' tool/e2e_live.sh [/path/to/evidence]
#
# Key auth instead of a password: MOAV_TEST_SSH_KEY=~/.ssh/key (the e2e test
# itself needs a password today; the key path is accepted for symmetry with
# tool/screenshots.sh and rejected with a clear message).
# Optional: MOAV_SIM_ID (default: first booted simulator), MOAV_TEST_PORT,
# MOAV_TEST_DOMAIN (blank = domainless), MOAV_TEST_ADMIN_PASSWORD,
# MOAV_TEST_E2E_DESELECT (profiles to untick on the Deploy form, optional:
# a domainless box works with the defaults), MOAV_TEST_E2E_USER,
# MOAV_TEST_E2E_CLEANUP=true.
# The install on a fresh box takes several minutes; the test allows 50.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-e2e-evidence}"
: "${MOAV_TEST_HOST:?set MOAV_TEST_HOST}"
if [[ -z "${MOAV_TEST_PASSWORD:-}" ]]; then
  echo "MOAV_TEST_PASSWORD is required (password auth is what this run proves)" >&2
  exit 1
fi

DEVICE="${MOAV_SIM_ID:-$(xcrun simctl list devices booted -j | python3 -c '
import json, sys
d = json.load(sys.stdin)
ids = [x["udid"] for v in d["devices"].values() for x in v if x["state"] == "Booted"]
print(ids[0] if ids else "")')}"
if [[ -z "$DEVICE" ]]; then
  echo "No booted iOS simulator (set MOAV_SIM_ID or boot one)" >&2
  exit 1
fi

DEFINES=(
  "--dart-define=MOAV_TEST_HOST=${MOAV_TEST_HOST}"
  "--dart-define=MOAV_TEST_USER=${MOAV_TEST_USER:-root}"
  "--dart-define=MOAV_TEST_PORT=${MOAV_TEST_PORT:-22}"
  "--dart-define=MOAV_TEST_PASSWORD_B64=$(printf '%s' "$MOAV_TEST_PASSWORD" | base64 | tr -d '\n')"
  "--dart-define=MOAV_TEST_DOMAIN=${MOAV_TEST_DOMAIN:-}"
  "--dart-define=MOAV_TEST_ADMIN_PASSWORD=${MOAV_TEST_ADMIN_PASSWORD:-}"
  "--dart-define=MOAV_TEST_E2E_USER=${MOAV_TEST_E2E_USER:-}"
  "--dart-define=MOAV_TEST_E2E_DESELECT=${MOAV_TEST_E2E_DESELECT:-}"
  "--dart-define=MOAV_TEST_E2E_CLEANUP=${MOAV_TEST_E2E_CLEANUP:-false}"
)
echo "e2e → ${MOAV_TEST_USER:-root}@${MOAV_TEST_HOST} on simulator ${DEVICE}, evidence in ${OUT}"

rm -rf shots build/integration_response_data.json && mkdir -p shots "$OUT"
set +e
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/e2e_live_test.dart \
  -d "$DEVICE" \
  "${DEFINES[@]}" 2>&1 | tee "$OUT/flutter-drive.log"
rc=${PIPESTATUS[0]}
set -e

cp -f shots/*.png "$OUT/" 2>/dev/null || true
if [[ -f build/integration_response_data.json ]]; then
  # Split the report: results.json (readable), install.log, bundle zip.
  python3 -I - "$OUT" <<'PY'
import base64, json, sys, os
out = sys.argv[1]
data = json.load(open("build/integration_response_data.json"))
data.pop("screenshots", None)  # PNG bytes, already saved from shots/
zip_b64 = data.pop("zipBase64", None)
log = data.pop("installLogTail", None)
with open(os.path.join(out, "results.json"), "w") as f:
    json.dump(data, f, indent=2)
if log is not None:
    with open(os.path.join(out, "install-deploy.log"), "w") as f:
        f.write("\n".join(log) + "\n")
if zip_b64:
    name = (data.get("5-bundle-zip") or {}).get("zipFileName") or "bundle.zip"
    with open(os.path.join(out, name), "wb") as f:
        f.write(base64.b64decode(zip_b64))
print(json.dumps({k: v.get("result") for k, v in data.items() if isinstance(v, dict) and "result" in v}, indent=2))
PY
else
  echo "no integration_response_data.json (test crashed before reporting?)" >&2
fi
ls -la "$OUT"
exit "$rc"
