#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
(cd core && go build -o bin/tailtap-core ./cmd/tailtap)
case "$(uname -s)" in
 Darwin)
   flutter build macos --debug
   app="build/macos/Build/Products/Debug/TailTap.app"
   cp core/bin/tailtap-core "$app/Contents/MacOS/tailtap-core"
   codesign --force --sign - --entitlements macos/Runner/Core.entitlements "$app/Contents/MacOS/tailtap-core"
   codesign --force --sign - --entitlements macos/Runner/DebugProfile.entitlements "$app"
   ;;
 Linux)
   flutter build linux
   cp core/bin/tailtap-core build/linux/x64/release/bundle/tailtap-core
   ;;
 *) echo 'For Windows, build the Go core and copy tailtap-core.exe beside the app executable.' ;;
esac
