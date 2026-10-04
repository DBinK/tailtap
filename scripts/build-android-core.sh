#!/bin/sh
set -eu
cd "$(dirname "$0")/../core"
license_assets=../build/license-assets/licenses
mkdir -p "$license_assets"
chmod -R u+w "$license_assets"
cp ../LICENSE ../THIRD_PARTY_NOTICES.md "$license_assets/"
cp -R ../third_party_licenses "$license_assets/"
ndk_version="${ANDROID_NDK_VERSION:-28.2.13676358}"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ndk="${ANDROID_NDK_HOME:-$sdk/ndk/$ndk_version}"
case "$(uname -s)-$(uname -m)" in
 Darwin-arm64)
   if [ -d "$ndk/toolchains/llvm/prebuilt/darwin-arm64" ]; then host=darwin-arm64; else host=darwin-x86_64; fi
   ;;
 Darwin-x86_64) host=darwin-x86_64 ;;
 Linux-x86_64) host=linux-x86_64 ;;
 Linux-aarch64|Linux-arm64) host=linux-aarch64 ;;
 *) echo "Unsupported Android NDK host: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
toolchain="$ndk/toolchains/llvm/prebuilt/$host/bin"
if [ ! -x "$toolchain/aarch64-linux-android24-clang" ]; then
 echo "Android NDK toolchain not found: $toolchain" >&2
 echo 'Install NDK 28.2.13676358 or set ANDROID_NDK_HOME.' >&2
 exit 1
fi
for abi in "${@:-arm64-v8a}"; do
 case "$abi" in arm64-v8a) arch=arm64; compiler=aarch64-linux-android24-clang ;; x86_64) arch=amd64; compiler=x86_64-linux-android24-clang ;; *) echo "Unsupported ABI: $abi" >&2; exit 1 ;; esac
 output="../android/app/src/main/jniLibs/$abi"
 mkdir -p "$output"
 CGO_ENABLED=1 GOOS=android GOARCH="$arch" CC="$toolchain/$compiler" go build -buildmode=c-shared -o "$output/libtailtap.so" ./mobile
 "$toolchain/$compiler" -shared -fPIC -I"$output" ../android/app/src/main/cpp/bridge.c -L"$output" -ltailtap -o "$output/libtailtap-jni.so"
done
