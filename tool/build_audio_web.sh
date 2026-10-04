#!/usr/bin/env bash
# Builds the Web sound engine (W04): bundles web_src/src/zywny_audio.js
# (SpessaSynth, Apache-2.0) with esbuild into web/audio/zywny_audio.js and
# copies the AudioWorklet processor next to it — the bundle loads it by
# relative URL. Needs node/npm and network on the first run. The output is
# not versioned (see .gitignore); `lib/audio/web_sound_engine.dart` imports
# the module lazily, so the Web build only downloads it when sound starts.
set -euo pipefail

proj_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$proj_dir/web_src"
out="$proj_dir/web/audio"

cd "$src"
npm install --no-audit --no-fund
mkdir -p "$out"
npx esbuild src/zywny_audio.js --bundle --format=esm --minify --target=es2022 \
    --outfile="$out/zywny_audio.js"
cp node_modules/spessasynth_lib/dist/spessasynth_processor.min.js "$out/"
ls -lh "$out"
