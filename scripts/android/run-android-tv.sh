#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH=; cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH=; cd -- "$SCRIPT_DIR/../.." && pwd)
MODE=${1:-debug}
ANDROID_TV_DEVICE=${ANDROID_TV_DEVICE:-Television_1080p}
EXPO_ANDROID_TV_DEVICE=$ANDROID_TV_DEVICE

case "$MODE" in
  -h|--help|help)
    printf 'Usage: sh scripts/android/run-android-tv.sh [debug|release] [expo-args...]\n'
    printf 'Set ANDROID_TV_DEVICE to override the default TV device: %s\n' "$ANDROID_TV_DEVICE"
    exit 0
    ;;
esac

if [ "$#" -gt 0 ]; then
  shift
fi

case "$MODE" in
  debug|release) ;;
  *)
    printf 'Usage: sh scripts/android/run-android-tv.sh [debug|release] [expo-args...]\n' >&2
    exit 2
    ;;
esac

cd "$REPO_ROOT"

wait_for_boot() {
  serial=$1
  attempt=1

  while [ "$attempt" -le 90 ]; do
    if [ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
      return 0
    fi

    attempt=$((attempt + 1))
    sleep 2
  done

  printf 'error: Android TV emulator %s did not boot\n' "$serial" >&2
  return 1
}

avd_name_for_serial() {
  serial=$1

  adb -s "$serial" emu avd name 2>/dev/null | sed -n '1p' | tr -d '\r'
}

serial_for_avd_name() {
  avd_name=$1

  adb devices | sed -n '2,$p' | while IFS="$(printf '\t')" read -r serial state _; do
    [ "$state" = "device" ] || continue
    [ "$(avd_name_for_serial "$serial")" = "$avd_name" ] || continue
    printf '%s\n' "$serial"
    break
  done
}

case "$ANDROID_TV_DEVICE" in
  emulator-*)
    resolved_name=$(avd_name_for_serial "$ANDROID_TV_DEVICE")
    if [ -n "$resolved_name" ]; then
      EXPO_ANDROID_TV_DEVICE=$resolved_name
    fi
    ;;
esac

if command -v adb >/dev/null 2>&1 && command -v emulator >/dev/null 2>&1; then
  booted_serial=$(serial_for_avd_name "$EXPO_ANDROID_TV_DEVICE")
  if [ -z "$booted_serial" ] && emulator -list-avds | grep -qx "$EXPO_ANDROID_TV_DEVICE"; then
    printf 'Starting Android TV emulator: %s\n' "$EXPO_ANDROID_TV_DEVICE"
    emulator -avd "$EXPO_ANDROID_TV_DEVICE" >/tmp/streamyfin-android-tv-emulator.log 2>&1 &
    sleep 3
    booted_serial=$(serial_for_avd_name "$EXPO_ANDROID_TV_DEVICE")
    if [ -n "$booted_serial" ]; then
      wait_for_boot "$booted_serial"
    fi
  fi
fi

prebuild_type=$(sh scripts/detect-prebuild-type.sh android)
if [ "$prebuild_type" = "tv" ]; then
  printf '%s\n' 'Prebuild already matches TV; skipping bun run prebuild:tv.'
else
  printf 'Current prebuild type: %s; running bun run prebuild:tv.\n' "$prebuild_type"
  bun run prebuild:tv
fi

printf 'Running Android TV on device: %s\n' "$EXPO_ANDROID_TV_DEVICE"
case "$MODE" in
  debug)
    EXPO_TV=1 exec expo run:android --device "$EXPO_ANDROID_TV_DEVICE" "$@"
    ;;
  release)
    EXPO_TV=1 exec expo run:android --device "$EXPO_ANDROID_TV_DEVICE" --variant release "$@"
    ;;
esac
