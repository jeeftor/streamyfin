#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  printf 'Usage: sh tests/maestro/run-android-emulator-flow.sh <device> <flow>\n' >&2
  exit 2
fi

device=$1
flow_name=$2
app_id=${MAESTRO_APP_ID:-com.fredrikburmester.streamyfin}
artifact_root=tests/maestro/artifacts
remote_video="/sdcard/streamyfin-${device}-play-steamboat.mp4"
local_video="${artifact_root}/videos/${device}-play-steamboat.mp4"
screenrecord_log="${artifact_root}/videos/${device}-screenrecord.log"
adb_debug_log="${artifact_root}/${device}-adb-debug.log"

adb_with_device() {
  if [ -n "${MAESTRO_DEVICE:-}" ]; then
    adb -s "$MAESTRO_DEVICE" "$@"
  else
    adb "$@"
  fi
}

take_adb_screenshot() {
  name=$1
  path="${artifact_root}/${name}.png"

  if adb_with_device exec-out screencap -p >"$path" 2>>"$adb_debug_log"; then
    printf 'Captured ADB screenshot: %s\n' "$path" | tee -a "$adb_debug_log"
  else
    rm -f "$path"
    printf 'warning: failed to capture ADB screenshot %s\n' "$path" | tee -a "$adb_debug_log" >&2
  fi
}

dump_adb_checkpoint() {
  label=$1
  screenshot_name=$2

  {
    printf '\n=== %s ===\n' "$label"
    date -u
    adb devices -l || true
    adb_with_device shell getprop sys.boot_completed || true
    adb_with_device shell getprop ro.build.version.release || true
    adb_with_device shell wm size || true
    adb_with_device shell wm density || true
    adb_with_device shell dumpsys window windows | sed -n '1,120p' || true
  } >>"$adb_debug_log" 2>&1

  take_adb_screenshot "$screenshot_name"
}

verify_apk_installed() {
  package_path=$(
    adb_with_device shell pm path "$app_id" 2>>"$adb_debug_log" | tr -d '\r' || true
  )

  if [ -z "$package_path" ]; then
    printf 'error: APK install did not register package %s\n' "$app_id" | tee -a "$adb_debug_log" >&2
    adb_with_device shell pm list packages | sed -n '1,160p' >>"$adb_debug_log" 2>&1 || true
    return 1
  fi

  printf 'Verified installed package %s: %s\n' "$app_id" "$package_path" | tee -a "$adb_debug_log"
}

copy_maestro_debug_artifacts() {
  target_dir="${artifact_root}/maestro-smoke-debug"
  [ -n "${HOME:-}" ] || return 0
  [ -d "$HOME/.maestro/tests" ] || return 0

  mkdir -p "$target_dir"
  find "$HOME/.maestro/tests" -mindepth 1 -maxdepth 1 -type d -exec cp -R {} "$target_dir/" \;
}

run_maestro_smoke_probe() {
  [ "${MAESTRO_DEBUG_SMOKE_ONLY:-0}" = "1" ] || return 0

  printf 'Running Maestro smoke probe only.\n' | tee -a "$adb_debug_log"
  mkdir -p "${artifact_root}/maestro-smoke"
  export MAESTRO_ARTIFACT_DIR="${artifact_root}/maestro-smoke"
  maestro --version >>"$adb_debug_log" 2>&1 || true

  set +e
  if [ -n "${MAESTRO_DEVICE:-}" ]; then
    maestro test --platform android --device "$MAESTRO_DEVICE" tests/maestro/flows/_launch.yaml
  else
    maestro test --platform android tests/maestro/flows/_launch.yaml
  fi
  smoke_status=$?
  set -e

  copy_maestro_debug_artifacts
  dump_adb_checkpoint "After Maestro smoke probe" "${device}-04-after-maestro-smoke"

  exit "$smoke_status"
}

wait_for_adb_ready() {
  label=$1
  attempt=1

  while [ "$attempt" -le 30 ]; do
    adb_with_device wait-for-device >/dev/null 2>&1 || true
    if [ "$(adb_with_device shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
      if adb_with_device shell true >/dev/null 2>&1; then
        printf 'ADB ready after %s (%s).\n' "$label" "$attempt"
        return 0
      fi
    fi

    attempt=$((attempt + 1))
    sleep 2
  done

  printf 'error: ADB did not become ready after %s\n' "$label" >&2
  adb devices -l >&2 || true
  return 1
}

stabilize_emulator_ui() {
  label=$1

  wait_for_adb_ready "$label"
  adb_with_device shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  adb_with_device shell wm dismiss-keyguard >/dev/null 2>&1 || true
  adb_with_device shell input keyevent KEYCODE_ESCAPE >/dev/null 2>&1 || true
  adb_with_device shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true

  # CI images sometimes surface a launcher ANR dialog before Maestro can launch the app.
  for launcher in \
    com.google.android.apps.nexuslauncher \
    com.google.android.apps.tv.launcherx \
    com.google.android.tvlauncher \
    com.android.launcher3
  do
    adb_with_device shell am force-stop "$launcher" >/dev/null 2>&1 || true
  done

  adb_with_device shell am force-stop "$app_id" >/dev/null 2>&1 || true
  sleep 2
}

mkdir -p "${artifact_root}/videos"
: >"$adb_debug_log"
wait_for_adb_ready "emulator boot"
dump_adb_checkpoint "After emulator boot" "${device}-01-after-boot"
stabilize_emulator_ui "initial UI stabilization"
dump_adb_checkpoint "After initial UI stabilization" "${device}-02-after-stabilize"
adb_with_device install -r android/app/build/outputs/apk/release/app-release.apk
verify_apk_installed
stabilize_emulator_ui "APK install"
dump_adb_checkpoint "After APK install" "${device}-03-after-apk-install"
run_maestro_smoke_probe

adb_with_device shell rm -f "$remote_video" >/dev/null 2>&1 || true
adb_with_device shell screenrecord --time-limit 180 "$remote_video" >"$screenrecord_log" 2>&1 &
screenrecord_pid=$!
sleep 2
wait_for_adb_ready "screenrecord start"

set +e
make jellyfin-configure-maestro-ids
configure_status=$?
if [ "$configure_status" -eq 0 ]; then
  wait_for_adb_ready "Maestro flow start"
  sh tests/maestro/run-flow.sh "$flow_name"
  test_status=$?
else
  test_status=$configure_status
fi
set -e

kill "$screenrecord_pid" >/dev/null 2>&1 || true
wait "$screenrecord_pid" >/dev/null 2>&1 || true
sleep 1

adb_with_device pull "$remote_video" "$local_video" >/dev/null 2>&1 || true
adb_with_device shell rm -f "$remote_video" >/dev/null 2>&1 || true

if [ ! -s "$local_video" ]; then
  if [ "$test_status" -eq 0 ]; then
    printf 'error: screenrecord did not produce %s\n' "$local_video" >&2
    if [ -f "$screenrecord_log" ]; then
      cat "$screenrecord_log" >&2
    fi
    test_status=1
  else
    printf 'warning: screenrecord did not produce %s after a failed flow\n' "$local_video" >&2
    if [ -f "$screenrecord_log" ]; then
      cat "$screenrecord_log" >&2
    fi
  fi
fi

exit "$test_status"
