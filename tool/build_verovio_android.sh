#!/usr/bin/env bash
# Builds libverovio.so for Android (arm64-v8a + x86_64 — device and
# emulator) from verovio_flutter_bridge and stages each one under
# android/app/src/main/jniLibs/<abi>/libverovio.so, the layout Gradle's
# default jniLibs source set packages into the APK. At runtime,
# DynamicLibrary.open('libverovio.so') (bare name, see lib/native_paths.dart)
# finds it there — no filesystem search needed like on Linux.
#
# The bridge's own build_android_so.sh already strips with the NDK's
# llvm-strip; this script just runs it and copies the result.
set -euo pipefail

proj_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dart_pkg="/home/mauricio/rust_projects/verovio_flutter_bridge/verovio/bindings/dart"
abis=(arm64-v8a x86_64)

[[ -x "$dart_pkg/build_android_so.sh" ]] || { echo "ERROR: /home/mauricio/rust_projects/verovio_flutter_bridge not found" >&2; exit 1; }

"$dart_pkg/build_android_so.sh" "${abis[@]}"

for abi in "${abis[@]}"; do
    src="$dart_pkg/android-libs/$abi/libverovio.so"
    dest_dir="$proj_dir/android/app/src/main/jniLibs/$abi"
    mkdir -p "$dest_dir"
    cp "$src" "$dest_dir/libverovio.so"
    ls -lh "$dest_dir/libverovio.so"
done
