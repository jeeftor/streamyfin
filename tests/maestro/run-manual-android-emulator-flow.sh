#!/bin/sh
set -eu

if [ "$#" -ne 5 ]; then
  printf 'Usage: sh tests/maestro/run-manual-android-emulator-flow.sh <device> <flow> <api-level> <target> <profile>\n' >&2
  exit 2
fi

device=$1
flow_name=$2
api_level=$3
target=$4
profile=$5
arch=x86_64
avd_name="streamyfin-${device}"
port=${EMULATOR_PORT:-5554}
serial="emulator-${port}"
android_home=${ANDROID_HOME:-/usr/local/lib/android/sdk}
artifact_dir=tests/maestro/artifacts
emulator_log="${artifact_dir}/${device}-emulator.log"
manual_log="${artifact_dir}/${device}-manual-emulator-debug.log"

export ANDROID_HOME="$android_home"
export ANDROID_SERIAL="$serial"
export MAESTRO_DEVICE="$serial"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

log_manual_checkpoint() {
  label=$1

  {
    printf '\n=== %s ===\n' "$label"
    date -u
    printf 'ANDROID_HOME=%s\n' "$ANDROID_HOME"
    printf 'ANDROID_SERIAL=%s\n' "$ANDROID_SERIAL"
    adb devices -l || true
  } >>"$manual_log" 2>&1
}

cleanup() {
  adb -s "$serial" emu kill >/dev/null 2>&1 || true
  if [ -n "${emulator_pid:-}" ]; then
    wait "$emulator_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

wait_for_emulator_boot() {
  attempt=1

  while [ "$attempt" -le 180 ]; do
    adb -s "$serial" wait-for-device >/dev/null 2>&1 || true
    if [ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
      if adb -s "$serial" shell true >/dev/null 2>&1; then
        printf 'Manual emulator booted after %s attempts.\n' "$attempt"
        return 0
      fi
    fi

    attempt=$((attempt + 1))
    sleep 2
  done

  printf 'error: manual emulator did not boot\n' >&2
  adb devices -l >&2 || true
  if [ -f "$emulator_log" ]; then
    tail -n 200 "$emulator_log" >&2
  fi
  return 1
}

mkdir -p "$artifact_dir"
: >"$manual_log"

package="system-images;android-${api_level};${target};${arch}"
printf 'Accepting Android SDK licenses.\n'
yes | sdkmanager --licenses >/dev/null
printf 'Installing Android SDK packages for %s.\n' "$package"
sdkmanager --install \
  "platform-tools" \
  "emulator" \
  "platforms;android-${api_level}" \
  "$package"
log_manual_checkpoint "Android SDK packages installed"

printf 'Creating AVD %s.\n' "$avd_name"
{
  printf '\n=== available AVD devices ===\n'
  avdmanager list device || true
} >>"$manual_log" 2>&1
printf 'no\n' | timeout 120 avdmanager create avd \
  --force \
  --name "$avd_name" \
  --abi "${target}/${arch}" \
  --package "$package" \
  --device "$profile"
log_manual_checkpoint "AVD created"

printf 'Starting manual Android emulator %s on %s.\n' "$avd_name" "$serial"
"$ANDROID_HOME/emulator/emulator" \
  -port "$port" \
  -avd "$avd_name" \
  -no-window \
  -gpu swiftshader_indirect \
  -no-snapshot \
  -noaudio \
  -no-boot-anim \
  >"$emulator_log" 2>&1 &
emulator_pid=$!

wait_for_emulator_boot
log_manual_checkpoint "Manual emulator booted"
sh tests/maestro/run-android-emulator-flow.sh "$device" "$flow_name"
