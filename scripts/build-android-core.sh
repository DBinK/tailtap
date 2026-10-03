#!/bin/sh
set -eu
cd "$(dirname "$0")/../core"
ndk="${ANDROID_NDK_HOME:-$HOME/Library/Android/sdk/ndk/28.2.13676358}"
toolchain="$ndk/toolchains/llvm/prebuilt/darwin-x86_64/bin"
for abi in arm64-v8a x86_64; do
 case "$abi" in arm64-v8a) arch=arm64; compiler=aarch64-linux-android24-clang ;; x86_64) arch=amd64; compiler=x86_64-linux-android24-clang ;; esac
 output="../android/app/src/main/jniLibs/$abi"
 mkdir -p "$output"
 CGO_ENABLED=1 GOOS=android GOARCH="$arch" CC="$toolchain/$compiler" go build -buildmode=c-shared -o "$output/libtailtap.so" ./mobile
 "$toolchain/$compiler" -shared -fPIC -I"$output" ../android/app/src/main/cpp/bridge.c -L"$output" -ltailtap -o "$output/libtailtap-jni.so"
done
