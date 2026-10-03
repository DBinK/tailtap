#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mode="${1:---debug}"
case "$mode" in --debug|--release) ;; *) echo 'Usage: build-desktop.sh [--debug|--release]' >&2; exit 1 ;; esac
case "$(uname -s)" in
 Darwin)
   if [ "$mode" = --release ]; then
     (cd core && CGO_ENABLED=0 GOARCH=arm64 go build -trimpath -ldflags='-s -w' -o bin/tailtap-core ./cmd/tailtap)
     configuration=Release
   else
     (cd core && go build -o bin/tailtap-core ./cmd/tailtap)
     configuration=Debug
   fi
   flutter build macos "$mode"
   app="build/macos/Build/Products/$configuration/TailTap.app"
   cp core/bin/tailtap-core "$app/Contents/MacOS/tailtap-core"
   mkdir -p "$app/Contents/Resources/licenses"
   cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/licenses/"
   cp -R third_party_licenses "$app/Contents/Resources/licenses/"
   codesign --force --sign - --entitlements macos/Runner/Core.entitlements "$app/Contents/MacOS/tailtap-core"
   if [ "$mode" = --release ]; then
     entitlements=macos/Runner/Release.entitlements
   else
     entitlements=macos/Runner/DebugProfile.entitlements
   fi
   codesign --force --sign - --entitlements "$entitlements" "$app"
   ;;
 Linux)
   (cd core && go build -o bin/tailtap-core ./cmd/tailtap)
   flutter build linux
   cp core/bin/tailtap-core build/linux/x64/release/bundle/tailtap-core
   ;;
 *) echo 'For Windows, build the Go core and copy tailtap-core.exe beside the app executable.' ;;
esac
