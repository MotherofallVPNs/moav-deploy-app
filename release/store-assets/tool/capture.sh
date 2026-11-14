#!/usr/bin/env bash
# Captures the raw store screenshots into build/store-shots/<target>/.
# Usage: capture.sh iphone|ipad|android   (see ../README.md)
set -euo pipefail

TARGET="${1:-}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TOOL="release/store-assets/tool"
PORT="${MOAV_SHOT_PORT:-45055}"
cd "$ROOT"

IPHONE_SIM="${MOAV_IPHONE_SIM:-iPhone 18 Pro Max}"
IPAD_SIM="${MOAV_IPAD_SIM:-iPad Pro 13-inch (M5)}"
ANDROID_AVD="${MOAV_ANDROID_AVD:-moav_api35}"

BOOTED_HERE=""
EMULATOR_PID=""
DEVICE=""
PREV_LOOK=""

sim_udid() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for runtime in json.load(sys.stdin)["devices"].values():
    for d in runtime:
        if d["name"] == name:
            print(d["udid"])
            sys.exit(0)
sys.exit(1)' "$1"
}

sim_state() {
  xcrun simctl list devices -j | python3 -c '
import json, sys
udid = sys.argv[1]
for runtime in json.load(sys.stdin)["devices"].values():
    for d in runtime:
        if d["udid"] == udid:
            print(d["state"])' "$1"
}

android_sdk() {
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -z "$sdk" && -f android/local.properties ]]; then
    sdk="$(sed -n 's/^sdk\.dir=//p' android/local.properties)"
  fi
  [[ -n "$sdk" ]] || { echo "Android SDK not found (set ANDROID_HOME)" >&2; exit 1; }
  printf '%s\n' "$sdk"
}

demo_mode() {
  adb -s "$DEVICE" shell am broadcast -a com.android.systemui.demo "$@" >/dev/null
}

cleanup() {
  case "$TARGET" in
    iphone | ipad)
      [[ -n "$DEVICE" ]] || return 0
      xcrun simctl status_bar "$DEVICE" clear >/dev/null 2>&1 || true
      case "$PREV_LOOK" in
        light | dark) xcrun simctl ui "$DEVICE" appearance "$PREV_LOOK" || true ;;
      esac
      xcrun simctl uninstall "$DEVICE" org.motherofallvpns.moavdeploy >/dev/null 2>&1 || true
      if [[ -n "$BOOTED_HERE" ]]; then xcrun simctl shutdown "$DEVICE" || true; fi
      ;;
    android)
      [[ -n "$DEVICE" ]] || return 0
      demo_mode -e command exit || true
      case "$PREV_LOOK" in
        yes | no | auto) adb -s "$DEVICE" shell cmd uimode night "$PREV_LOOK" >/dev/null || true ;;
      esac
      adb -s "$DEVICE" reverse --remove "tcp:$PORT" >/dev/null 2>&1 || true
      adb -s "$DEVICE" uninstall org.motherofallvpns.moavdeploy >/dev/null 2>&1 || true
      if [[ -n "$EMULATOR_PID" ]]; then
        adb -s "$DEVICE" emu kill >/dev/null 2>&1 || true
        wait "$EMULATOR_PID" 2>/dev/null || true
      fi
      ;;
  esac
}
trap cleanup EXIT

case "$TARGET" in
  iphone | ipad)
    NAME="$IPHONE_SIM"
    [[ "$TARGET" == ipad ]] && NAME="$IPAD_SIM"
    DEVICE="$(sim_udid "$NAME")" || { echo "No simulator named '$NAME'" >&2; exit 1; }
    if [[ "$(sim_state "$DEVICE")" != Booted ]]; then
      xcrun simctl boot "$DEVICE"
      BOOTED_HERE=1
    fi
    xcrun simctl bootstatus "$DEVICE" -b >/dev/null
    PREV_LOOK="$(xcrun simctl ui "$DEVICE" appearance 2>/dev/null || true)"
    xcrun simctl ui "$DEVICE" appearance dark
    xcrun simctl status_bar "$DEVICE" override --time "9:41" \
      --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --cellularMode active --cellularBars 4 --operatorName "" \
      --batteryState discharging --batteryLevel 100
    CAPTURE="simctl:$DEVICE"
    ;;
  android)
    SDK="$(android_sdk)"
    DEVICE="$(adb devices | awk '$1 ~ /^emulator-/ && $2 == "device" { print $1; exit }')"
    if [[ -z "$DEVICE" ]]; then
      "$SDK/emulator/emulator" -avd "$ANDROID_AVD" -no-snapshot-save -no-audio \
        -no-boot-anim -no-window >/dev/null 2>&1 &
      EMULATOR_PID=$!
      adb wait-for-device
      DEVICE="$(adb devices | awk '$1 ~ /^emulator-/ { print $1; exit }')"
      until [[ "$(adb -s "$DEVICE" shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]; do
        sleep 2
      done
      # SystemUI ignores demo-mode broadcasts for a while after boot.
      sleep 20
    fi
    PREV_LOOK="$(adb -s "$DEVICE" shell cmd uimode night | tr -d '\r' | sed -n 's/^Night mode: //p')"
    adb -s "$DEVICE" shell cmd uimode night yes >/dev/null
    adb -s "$DEVICE" shell settings put global sysui_demo_allowed 1
    demo_mode -e command enter
    demo_mode -e command clock -e hhmm 0941
    demo_mode -e command battery -e level 100 -e plugged false
    demo_mode -e command network -e mobile hide
    demo_mode -e command network -e wifi show -e level 4 -e fully true
    demo_mode -e command notifications -e visible false
    demo_mode -e command status -e volume hide -e bluetooth hide -e alarm hide
    # Loopback through adb: works even before the emulator's Wi-Fi is up.
    adb -s "$DEVICE" reverse "tcp:$PORT" "tcp:$PORT" >/dev/null
    CAPTURE="adb:$DEVICE"
    ;;
  *)
    echo "usage: $0 iphone|ipad|android" >&2
    exit 64
    ;;
esac

OUT="build/store-shots/$TARGET"
rm -rf "$OUT"
mkdir -p "$OUT"

MOAV_SHOT_CAPTURE="$CAPTURE" MOAV_SHOT_DIR="$OUT" MOAV_SHOT_PORT="$PORT" \
  flutter drive \
  --driver="$TOOL/store_shots_driver.dart" \
  --target="$TOOL/store_shots.dart" \
  --dart-define="MOAV_SHOT_PORT=$PORT" \
  -d "$DEVICE"

echo "raw shots in $OUT:"
ls "$OUT"
