#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  printf 'Usage: sh tests/maestro/run-tv-debug-step.sh install-sdk|create-avd|start|install-apk|adb-launch|maestro-smoke|maestro-flow|stop\n' >&2
  exit 2
fi

step=$1
api_level=${TV_API_LEVEL:?}
target=${TV_EMULATOR_TARGET:?}
profile=${TV_EMULATOR_PROFILE:?}
arch=${TV_EMULATOR_ARCH:-x86_64}
avd_name=${TV_AVD_NAME:-streamyfin-tv}
port=${TV_EMULATOR_PORT:-5554}
serial="emulator-${port}"
android_home=${ANDROID_HOME:-/usr/local/lib/android/sdk}
android_avd_home=${ANDROID_AVD_HOME:-$HOME/.android/avd}
artifact_dir=tests/maestro/artifacts
emulator_log="${artifact_dir}/tv-emulator.log"
pid_file="${artifact_dir}/tv-emulator.pid"
debug_log="${artifact_dir}/tv-debug-step.log"
app_id=${MAESTRO_APP_ID:-com.fredrikburmester.streamyfin}
flow_name=${MAESTRO_FLOW_NAME:-tv-play-steamboat-willie}
apk_path=android/app/build/outputs/apk/release/app-release.apk
package="system-images;android-${api_level};${target};${arch}"
remote_video="/sdcard/streamyfin-tv-play-steamboat.mp4"
local_video="${artifact_dir}/videos/tv-play-steamboat.mp4"
screenrecord_log="${artifact_dir}/videos/tv-screenrecord.log"

export ANDROID_HOME="$android_home"
export ANDROID_AVD_HOME="$android_avd_home"
export ANDROID_SERIAL="$serial"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

adb_device() {
  adb -s "$serial" "$@"
}

log_section() {
  label=$1

  {
    printf '\n=== %s ===\n' "$label"
    date -u
    printf 'ANDROID_HOME=%s\n' "$ANDROID_HOME"
    printf 'ANDROID_AVD_HOME=%s\n' "$ANDROID_AVD_HOME"
    printf 'ANDROID_SERIAL=%s\n' "$ANDROID_SERIAL"
    adb devices -l || true
  } | tee -a "$debug_log"
}

take_screenshot() {
  name=$1
  path="${artifact_dir}/${name}.png"

  if adb_device exec-out screencap -p >"$path" 2>>"$debug_log"; then
    printf 'Captured ADB screenshot: %s\n' "$path" | tee -a "$debug_log"
  else
    rm -f "$path"
    printf 'warning: failed to capture ADB screenshot %s\n' "$path" | tee -a "$debug_log" >&2
  fi
}

dump_device_state() {
  label=$1
  screenshot_name=$2

  wait_for_adb_device "$label"
  log_section "$label"
  {
    adb_device shell getprop sys.boot_completed || true
    adb_device shell getprop ro.build.version.release || true
    adb_device shell wm size || true
    adb_device shell wm density || true
    adb_device shell dumpsys window windows | sed -n '1,120p' || true
  } >>"$debug_log" 2>&1
  take_screenshot "$screenshot_name"
}

wait_for_adb_device() {
  label=$1
  attempt=1

  while [ "$attempt" -le 60 ]; do
    if adb_device shell true >/dev/null 2>&1; then
      printf '%s: adb device ready after %s attempts.\n' "$label" "$attempt" | tee -a "$debug_log"
      return 0
    fi

    attempt=$((attempt + 1))
    sleep 2
  done

  printf 'error: %s: adb device did not become ready\n' "$label" | tee -a "$debug_log" >&2
  adb devices -l | tee -a "$debug_log" >&2 || true
  return 1
}

wait_for_boot() {
  attempt=1
  ready_count=0

  while [ "$attempt" -le 180 ]; do
    adb_device wait-for-device >/dev/null 2>&1 || true
    if [ "$(adb_device shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
      if adb_device shell true >/dev/null 2>&1; then
        ready_count=$((ready_count + 1))
        if [ "$ready_count" -ge 3 ]; then
          printf 'TV emulator booted after %s attempts.\n' "$attempt" | tee -a "$debug_log"
          return 0
        fi
      else
        ready_count=0
      fi
    else
      ready_count=0
    fi

    attempt=$((attempt + 1))
    sleep 2
  done

  printf 'error: TV emulator did not boot\n' | tee -a "$debug_log" >&2
  adb devices -l | tee -a "$debug_log" >&2 || true
  if [ -f "$emulator_log" ]; then
    tail -n 200 "$emulator_log" | tee -a "$debug_log" >&2
  fi
  return 1
}

stabilize_ui() {
  adb_device shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  adb_device shell wm dismiss-keyguard >/dev/null 2>&1 || true
  adb_device shell input keyevent KEYCODE_ESCAPE >/dev/null 2>&1 || true
  adb_device shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true

  for launcher in \
    com.google.android.apps.nexuslauncher \
    com.google.android.apps.tv.launcherx \
    com.google.android.tvlauncher \
    com.android.launcher3
  do
    adb_device shell am force-stop "$launcher" >/dev/null 2>&1 || true
  done

  adb_device shell am force-stop "$app_id" >/dev/null 2>&1 || true
  sleep 2
}

launch_app_with_adb() {
  adb_device shell pm clear "$app_id" >/dev/null 2>&1 || true
  wait_for_adb_device "After app data clear"

  launcher_activity=$(
    adb_device shell cmd package resolve-activity --brief "$app_id" 2>>"$debug_log" \
      | tr -d '\r' \
      | tail -n 1
  )

  if [ -n "$launcher_activity" ]; then
    adb_device shell am start -n "$launcher_activity" >>"$debug_log" 2>&1
    printf 'Launched %s with adb am start %s.\n' "$app_id" "$launcher_activity" | tee -a "$debug_log"
  elif adb_device shell monkey -p "$app_id" -c android.intent.category.LAUNCHER 1 >>"$debug_log" 2>&1; then
    printf 'Launched %s with adb monkey.\n' "$app_id" | tee -a "$debug_log"
  else
    printf 'error: unable to launch %s with resolved activity or adb monkey\n' "$app_id" | tee -a "$debug_log" >&2
    return 1
  fi

  sleep 8
  wait_for_adb_device "After app launch"
}

copy_maestro_debug_artifacts() {
  target_dir="${artifact_dir}/maestro-debug"
  [ -n "${HOME:-}" ] || return 0
  [ -d "$HOME/.maestro/tests" ] || return 0

  mkdir -p "$target_dir"
  find "$HOME/.maestro/tests" -mindepth 1 -maxdepth 1 -type d -exec cp -R {} "$target_dir/" \;
}

run_maestro_flow() {
  log_section "Run Maestro TV flow"
  mkdir -p "${artifact_dir}/videos"
  export MAESTRO_DEVICE="$serial"
  export MAESTRO_PLATFORM=android
  export MAESTRO_TARGET=android-tv

  wait_for_adb_device "Before Maestro TV flow"
  adb_device shell rm -f "$remote_video" >/dev/null 2>&1 || true
  adb_device shell screenrecord --time-limit 180 "$remote_video" >"$screenrecord_log" 2>&1 &
  screenrecord_pid=$!
  sleep 2
  wait_for_adb_device "After TV screenrecord start"

  set +e
  make jellyfin-configure-maestro-ids
  configure_status=$?
  if [ "$configure_status" -eq 0 ]; then
    sh tests/maestro/run-flow.sh "$flow_name"
    test_status=$?
  else
    test_status=$configure_status
  fi
  set -e

  kill "$screenrecord_pid" >/dev/null 2>&1 || true
  wait "$screenrecord_pid" >/dev/null 2>&1 || true
  sleep 1

  copy_maestro_debug_artifacts
  adb_device pull "$remote_video" "$local_video" >/dev/null 2>&1 || true
  adb_device shell rm -f "$remote_video" >/dev/null 2>&1 || true

  if [ ! -s "$local_video" ]; then
    if [ "$test_status" -eq 0 ]; then
      printf 'error: screenrecord did not produce %s\n' "$local_video" | tee -a "$debug_log" >&2
      if [ -f "$screenrecord_log" ]; then
        cat "$screenrecord_log" | tee -a "$debug_log" >&2
      fi
      test_status=1
    else
      printf 'warning: screenrecord did not produce %s after a failed flow\n' "$local_video" | tee -a "$debug_log" >&2
      if [ -f "$screenrecord_log" ]; then
        cat "$screenrecord_log" | tee -a "$debug_log" >&2
      fi
    fi
  fi

  dump_device_state "After Maestro TV flow" "tv-04-after-maestro-flow"
  exit "$test_status"
}

mkdir -p "$artifact_dir" "$ANDROID_AVD_HOME"

case "$step" in
  install-sdk)
    : >"$debug_log"
    log_section "Install TV emulator SDK"
    yes | sdkmanager --licenses >/dev/null
    sdkmanager --install \
      "platform-tools" \
      "emulator" \
      "platforms;android-${api_level}" \
      "$package"
    ;;
  create-avd)
    log_section "Create TV AVD"
    avdmanager list device | tee -a "$debug_log"
    printf 'no\n' | timeout 120 avdmanager create avd \
      --force \
      --name "$avd_name" \
      --abi "${target}/${arch}" \
      --package "$package" \
      --device "$profile"
    avdmanager list avd | tee -a "$debug_log"
    ;;
  start)
    log_section "Start TV emulator"
    nohup "$ANDROID_HOME/emulator/emulator" \
      -port "$port" \
      -avd "$avd_name" \
      -no-window \
      -gpu swiftshader_indirect \
      -no-snapshot \
      -noaudio \
      -no-boot-anim \
      >"$emulator_log" 2>&1 &
    printf '%s\n' "$!" >"$pid_file"
    wait_for_boot
    wait_for_adb_device "After TV emulator boot"
    stabilize_ui
    dump_device_state "After TV emulator boot" "tv-01-after-boot"
    ;;
  install-apk)
    log_section "Install TV APK"
    test -f "$apk_path"
    wait_for_adb_device "Before TV APK install"
    adb_device install -r "$apk_path"
    package_path=$(adb_device shell pm path "$app_id" 2>>"$debug_log" | tr -d '\r' || true)
    if [ -z "$package_path" ]; then
      printf 'error: APK install did not register package %s\n' "$app_id" | tee -a "$debug_log" >&2
      adb_device shell pm list packages | sed -n '1,160p' >>"$debug_log" 2>&1 || true
      exit 1
    fi
    printf 'Verified installed package %s: %s\n' "$app_id" "$package_path" | tee -a "$debug_log"
    stabilize_ui
    dump_device_state "After TV APK install" "tv-02-after-apk-install"
    ;;
  adb-launch)
    log_section "ADB launch TV app"
    launch_app_with_adb
    dump_device_state "After ADB TV app launch" "tv-03-after-adb-launch"
    ;;
  maestro-smoke)
    log_section "Run Maestro TV smoke"
    mkdir -p "${artifact_dir}/maestro-smoke"
    export MAESTRO_ARTIFACT_DIR="${artifact_dir}/maestro-smoke"
    maestro --version | tee -a "$debug_log" || true
    wait_for_adb_device "Before Maestro TV smoke"
    set +e
    maestro test --platform android --device "$serial" tests/maestro/flows/tv-attach-smoke.yaml
    status=$?
    set -e
    copy_maestro_debug_artifacts
    dump_device_state "After Maestro TV smoke" "tv-04-after-maestro-smoke"
    exit "$status"
    ;;
  maestro-flow)
    run_maestro_flow
    ;;
  stop)
    log_section "Stop TV emulator"
    adb_device emu kill >/dev/null 2>&1 || true
    if [ -f "$pid_file" ]; then
      kill "$(cat "$pid_file")" >/dev/null 2>&1 || true
    fi
    ;;
  *)
    printf 'error: unknown TV debug step %s\n' "$step" >&2
    exit 2
    ;;
esac
