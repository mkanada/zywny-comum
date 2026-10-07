#!/usr/bin/env bash
# Stages the Verovio wasm toolkit for the Web build: runs the bridge's
# bindings/js/build_wasm.sh (Emscripten; incremental after the first build,
# which takes ~10 min) and copies the result to web/verovio/, where
# web/verovio_worker.js loads it from. The wasm is embedded in the .js
# (SINGLE_FILE) together with the engraving resources, so that single file is
# all there is — ~15 MB, ~4.8 MB gzipped. Not versioned (see .gitignore).
#
# Pass --no-build to only copy what the bridge built last.
set -euo pipefail

proj_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$(dirname "${BASH_SOURCE[0]}")/verovio_bridge.sh"
bridge="$verovio_bridge"
built="$bridge/verovio/emscripten/build/verovio-toolkit-hum.js"

if [[ "${1:-}" != "--no-build" ]]; then
    [[ -x "$bridge/verovio/bindings/js/build_wasm.sh" ]] || { echo "ERROR: $bridge not found" >&2; exit 1; }
    "$bridge/verovio/bindings/js/build_wasm.sh"
fi

[[ -f "$built" ]] || { echo "ERROR: $built missing — run without --no-build" >&2; exit 1; }
mkdir -p "$proj_dir/web/verovio"
cp "$built" "$proj_dir/web/verovio/verovio-toolkit-hum.js"
ls -lh "$proj_dir/web/verovio/verovio-toolkit-hum.js"
