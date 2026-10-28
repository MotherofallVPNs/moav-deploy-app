#!/usr/bin/env bash
# Captures the demo screenshot gallery on a booted iOS simulator into shots/.
#
# Built-in demo data by default. To drive a real server instead:
#   MOAV_TEST_SSH_KEY=~/.ssh/key MOAV_TEST_HOST=your.server \
#   MOAV_TEST_USER=root tool/screenshots.sh
# or with password auth: MOAV_TEST_PASSWORD='...' instead of MOAV_TEST_SSH_KEY.
# The live run is read-only except for one throwaway zzmoavdeploytest* user
# that is created for the bundle/QR shot and revoked afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${MOAV_SIM_ID:-$(xcrun simctl list devices booted -j | python3 -c '
import json, sys
d = json.load(sys.stdin)
ids = [x["udid"] for v in d["devices"].values() for x in v if x["state"] == "Booted"]
print(ids[0] if ids else "")')}"
if [[ -z "$DEVICE" ]]; then
  echo "No booted iOS simulator (set MOAV_SIM_ID or boot one)" >&2
  exit 1
fi

DEFINES=()
if [[ -n "${MOAV_TEST_HOST:-}" && ( -n "${MOAV_TEST_SSH_KEY:-}" || -n "${MOAV_TEST_PASSWORD:-}" ) ]]; then
  DEFINES+=(
    "--dart-define=MOAV_TEST_HOST=${MOAV_TEST_HOST}"
    "--dart-define=MOAV_TEST_USER=${MOAV_TEST_USER:-root}"
    "--dart-define=MOAV_TEST_PORT=${MOAV_TEST_PORT:-22}"
  )
  if [[ -n "${MOAV_TEST_SSH_KEY:-}" ]]; then
    KEY="${MOAV_TEST_SSH_KEY/#\~/$HOME}"
    DEFINES+=("--dart-define=MOAV_TEST_SSH_KEY_B64=$(base64 < "$KEY" | tr -d '\n')")
    echo "live mode (key) → ${MOAV_TEST_USER:-root}@${MOAV_TEST_HOST}"
  else
    DEFINES+=("--dart-define=MOAV_TEST_PASSWORD_B64=$(printf '%s' "$MOAV_TEST_PASSWORD" | base64 | tr -d '\n')")
    echo "live mode (password) → ${MOAV_TEST_USER:-root}@${MOAV_TEST_HOST}"
  fi
else
  echo "fake mode (set MOAV_TEST_HOST + MOAV_TEST_SSH_KEY or MOAV_TEST_PASSWORD for live data)"
fi

rm -rf shots && mkdir -p shots
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshots_test.dart \
  -d "$DEVICE" \
  "${DEFINES[@]}" "$@"
ls -la shots
