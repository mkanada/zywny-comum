#!/usr/bin/env bash
# Builds libzywny_audio.so for Android (arm64-v8a + x86_64 — device and
# emulator) with cargo-ndk and stages each one under
# android/app/src/main/jniLibs/<abi>/, next to libverovio.so. At runtime
# DynamicLibrary.open('libzywny_audio.so') (bare name) finds it there.
#
# Needs: rustup targets aarch64-linux-android x86_64-linux-android,
# `cargo install cargo-ndk`, an NDK under ~/Android/Sdk/ndk/.
set -euo pipefail

proj_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
crate_dir="$proj_dir/native/zywny_audio"
jni_dir="$proj_dir/android/app/src/main/jniLibs"

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
    ANDROID_NDK_HOME="$HOME/Android/Sdk/ndk/$(ls "$HOME/Android/Sdk/ndk" | sort -V | tail -n 1)"
    export ANDROID_NDK_HOME
fi

# Google Play requires 16 KB page alignment for new apps.
export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-z,max-page-size=16384"

(cd "$crate_dir" && cargo ndk -P 26 -t arm64-v8a -t x86_64 -o "$jni_dir" build --release)
ls -lh "$jni_dir"/*/libzywny_audio.so
