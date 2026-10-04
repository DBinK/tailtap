#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mode=debug
abi=arm64-v8a
platform=android-arm64
for arg in "$@"; do
 case "$arg" in
  --debug) mode=debug ;;
  --release) mode=release ;;
  --arm64|arm64|arm64-v8a) abi=arm64-v8a; platform=android-arm64 ;;
  --x86_64|x86_64|--x86|x86) abi=x86_64; platform=android-x64 ;;
  -h|--help) echo 'Usage: build-android.sh [--debug|--release] [--arm64|--x86_64]'; exit 0 ;;
  *) echo "Unknown argument: $arg" >&2; exit 2 ;;
 esac
done
flutter pub get
sh scripts/build-android-core.sh "$abi"
flutter build apk "--$mode" --target-platform "$platform" --split-per-abi
echo "APK: build/app/outputs/flutter-apk/app-$abi-$mode.apk"
