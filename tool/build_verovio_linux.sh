#!/usr/bin/env bash
# Builds libverovio.so from the third_party/verovio_lottie submodule and
# strips debug symbols (unstripped Android .so files were ~10x bigger).
#
# Output: third_party/verovio_lottie/verovio/bindings/dart/libverovio.so,
# which linux/CMakeLists.txt installs into the app bundle's lib/ dir.
set -euo pipefail

proj_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dart_pkg="$proj_dir/third_party/verovio_lottie/verovio/bindings/dart"

[[ -x "$dart_pkg/build_linux_so.sh" ]] || { echo "ERROR: submodule not checked out?" >&2; exit 1; }

"$dart_pkg/build_linux_so.sh"
strip --strip-unneeded "$dart_pkg/libverovio.so"
ls -lh "$dart_pkg/libverovio.so"
