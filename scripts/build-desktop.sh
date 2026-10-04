#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mode=--debug
arch=arm64
goarch=arm64
for arg in "$@"; do
 case "$arg" in
  --debug|--release) mode="$arg" ;;
  --arm64|arm64) arch=arm64; goarch=arm64 ;;
  --x86_64|x86_64|--x86|x86) arch=x86_64; goarch=amd64 ;;
  -h|--help) echo 'Usage: build-desktop.sh [--debug|--release] [--arm64|--x86_64]'; exit 0 ;;
  *) echo "Unknown argument: $arg" >&2; exit 2 ;;
 esac
done
flutter pub get
case "$(uname -s)" in
 Darwin)
   if [ "$mode" = --release ]; then
     (cd core && CGO_ENABLED=0 GOARCH="$goarch" go build -trimpath -ldflags='-s -w' -o bin/tailtap-core ./cmd/tailtap)
     configuration=Release
   else
     (cd core && CGO_ENABLED=0 GOARCH="$goarch" go build -o bin/tailtap-core ./cmd/tailtap)
     configuration=Debug
   fi
   flutter build macos "$mode" --config-only
   xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration "$configuration" -derivedDataPath build/macos -destination 'generic/platform=macOS' "ARCHS=$arch" ONLY_ACTIVE_ARCH=NO -quiet
   app="build/macos/Build/Products/$configuration/TailTap.app"
   cp core/bin/tailtap-core "$app/Contents/MacOS/tailtap-core"
   mkdir -p "$app/Contents/Resources/licenses"
   chmod -R u+w "$app/Contents/Resources/licenses"
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
   linuxarch=arm64
   if [ "$goarch" = amd64 ]; then linuxarch=x64; fi
   flutter build linux "$mode" --target-platform "linux-$linuxarch"
   bundle="build/linux/$goarch/${mode#--}/bundle"
   if [ "$goarch" = amd64 ]; then bundle="build/linux/x64/${mode#--}/bundle"; fi
   (cd core && CGO_ENABLED=0 GOARCH="$goarch" go build -o bin/tailtap-core ./cmd/tailtap)
   cp core/bin/tailtap-core "$bundle/tailtap-core"
   ;;
 *) echo 'For Windows, build the Go core and copy tailtap-core.exe beside the app executable.' ;;
esac
