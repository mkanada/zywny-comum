#!/usr/bin/env bash
# Builds libverovio.so from verovio_flutter_bridge (see tool/verovio_bridge.sh)
# and strips debug symbols (unstripped Android .so files were ~10x bigger).
#
# Output:
# <bridge>/verovio/bindings/dart/libverovio.so,
# which linux/CMakeLists.txt installs into the app bundle's lib/ dir.
set -euo pipefail

proj_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$(dirname "${BASH_SOURCE[0]}")/verovio_bridge.sh"
dart_pkg="$verovio_bridge/verovio/bindings/dart"

[[ -x "$dart_pkg/build_linux_so.sh" ]] || { echo "ERROR: $verovio_bridge not found (set VEROVIO_BRIDGE)" >&2; exit 1; }

"$dart_pkg/build_linux_so.sh"
strip --strip-unneeded "$dart_pkg/libverovio.so"
ls -lh "$dart_pkg/libverovio.so"
