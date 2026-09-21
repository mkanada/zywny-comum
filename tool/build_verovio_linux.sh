#!/usr/bin/env bash
# Builds libverovio.so from /home/mauricio/rust_projects/verovio_flutter_bridge
# and strips debug symbols (unstripped Android .so files were ~10x bigger).
#
# Output:
# /home/mauricio/rust_projects/verovio_flutter_bridge/verovio/bindings/dart/libverovio.so,
# which linux/CMakeLists.txt installs into the app bundle's lib/ dir.
set -euo pipefail

proj_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dart_pkg="/home/mauricio/rust_projects/verovio_flutter_bridge/verovio/bindings/dart"

[[ -x "$dart_pkg/build_linux_so.sh" ]] || { echo "ERROR: /home/mauricio/rust_projects/verovio_flutter_bridge not found" >&2; exit 1; }

"$dart_pkg/build_linux_so.sh"
strip --strip-unneeded "$dart_pkg/libverovio.so"
ls -lh "$dart_pkg/libverovio.so"
