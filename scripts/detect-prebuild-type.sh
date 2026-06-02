#!/bin/sh
# Detect whether the generated native project currently targets phone or TV.
#
# Output:
#   phone   generated native project exists and has no TV markers
#   tv      generated native project contains TV markers
#   unknown generated native project is missing or not recognizable
#
# Usage:
#   sh scripts/detect-prebuild-type.sh [android|ios]

set -eu

REPO_ROOT=$(CDPATH=; cd -- "$(dirname -- "$0")/.." && pwd)
IOS_DIR="$REPO_ROOT/ios"
ANDROID_DIR="$REPO_ROOT/android"

detect_ios() {
  podfile="$IOS_DIR/Podfile"
  pbx="$IOS_DIR/Streamyfin.xcodeproj/project.pbxproj"

  if [ -f "$podfile" ] && grep -q "platform :tvos" "$podfile"; then
    printf 'tv\n'
    return 0
  fi

  if [ -f "$pbx" ]; then
    if grep -q "TARGETED_DEVICE_FAMILY = 3" "$pbx" 2>/dev/null; then
      printf 'tv\n'
      return 0
    fi
    if grep -q "SDKROOT = appletvos" "$pbx" 2>/dev/null; then
      printf 'tv\n'
      return 0
    fi
    if grep -q "TVAppIcon" "$pbx" 2>/dev/null; then
      printf 'tv\n'
      return 0
    fi
  fi

  if [ -d "$IOS_DIR/Streamyfin/Images.xcassets/TVAppIcon.appiconset" ]; then
    printf 'tv\n'
    return 0
  fi

  if [ -f "$IOS_DIR/.xcode.env.local" ] && grep -q "EXPO_TV=1" "$IOS_DIR/.xcode.env.local"; then
    printf 'tv\n'
    return 0
  fi

  if [ -d "$IOS_DIR/Streamyfin.xcodeproj" ] || [ -f "$podfile" ]; then
    printf 'phone\n'
    return 0
  fi

  return 1
}

detect_android() {
  manifest="$ANDROID_DIR/app/src/main/AndroidManifest.xml"

  if [ -f "$manifest" ]; then
    if grep -q "android.software.leanback" "$manifest"; then
      printf 'tv\n'
      return 0
    fi
    if grep -q 'android.hardware.touchscreen.*required.*false' "$manifest"; then
      printf 'tv\n'
      return 0
    fi

    printf 'phone\n'
    return 0
  fi

  return 1
}

case "${1:-any}" in
  ios)
    detect_ios 2>/dev/null || printf 'unknown\n'
    ;;
  android)
    detect_android 2>/dev/null || printf 'unknown\n'
    ;;
  any)
    if detect_ios 2>/dev/null; then
      exit 0
    fi

    if detect_android 2>/dev/null; then
      exit 0
    fi

    printf 'unknown\n'
    ;;
  *)
    printf 'Usage: sh scripts/detect-prebuild-type.sh [android|ios]\n' >&2
    exit 2
    ;;
esac
