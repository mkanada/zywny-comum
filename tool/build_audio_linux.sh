#!/usr/bin/env bash
# Builds libzywny_audio.so from native/zywny_audio (this repo) and strips
# debug symbols, the same treatment tool/build_verovio_linux.sh gives
# libverovio.so.
#
# Output: native/zywny_audio/target/release/libzywny_audio.so, which
# linux/CMakeLists.txt installs into the app bundle's lib/ dir.
set -euo pipefail

proj_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
crate_dir="$proj_dir/native/zywny_audio"

(cd "$crate_dir" && cargo build --release)
strip --strip-unneeded "$crate_dir/target/release/libzywny_audio.so"
ls -lh "$crate_dir/target/release/libzywny_audio.so"
