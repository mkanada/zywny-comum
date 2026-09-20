#!/usr/bin/env bash
# Regenerates assets/verovio_data.zip from the submodule's verovio/data —
# the engraving resources Verovio needs at runtime (SMuFL fonts Bravura,
# Leipzig, Gootville, Petaluma, Leland, plus the Liberation TTFs and text
# metrics in data/text).
#
# Packed as a single zip rather than raw files because Flutter's asset
# bundler lists a directory non-recursively: declaring assets/verovio_data/
# in pubspec.yaml would silently drop every per-glyph subfolder.
# lib/verovio_resources.dart unpacks it on first launch and hands the
# directory to the Toolkit as its resourcePath.
#
# Not versioned (see .gitignore) — regenerable and derived from the
# submodule. Re-run after updating third_party/verovio_flutter_bridge.
set -euo pipefail

proj_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$proj_dir/third_party/verovio_flutter_bridge/verovio/data"
dst="$proj_dir/assets/verovio_data.zip"

[[ -d "$src" ]] || { echo "ERROR: directory not found: $src (submodule checked out?)" >&2; exit 1; }
command -v zip >/dev/null || { echo "ERROR: 'zip' not installed" >&2; exit 1; }

mkdir -p "$(dirname "$dst")"
rm -f "$dst"
(cd "$src" && zip -rq -X "$dst" .)
echo "Generated $dst ($(du -h "$dst" | cut -f1), from $src)"
