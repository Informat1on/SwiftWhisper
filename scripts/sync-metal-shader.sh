#!/usr/bin/env bash
# Generate Sources/whisper_metal/ggml-metal.metal from the whisper.cpp submodule.
#
# Two problems this solves, both of which silently disable the Metal backend:
#
# 1. A symlink here does not survive SwiftPM resource packaging — SwiftPM copies
#    resources into <Target>.bundle verbatim, so a relative symlink ends up
#    dangling and ggml_metal_load_library() cannot read the shader source.
#
# 2. ggml-metal.metal `#include`s "ggml-common.h" and "ggml-metal-impl.h".  When
#    ggml compiles the shader at runtime via -newLibraryWithSource: there is no
#    include search path, so those headers only resolve if they happen to sit in
#    the process working directory.  Inside an .app they never do.
#    We therefore inline them here, exactly like the CMake GGML_METAL_EMBED_LIBRARY
#    path does, and ship one self-contained .metal file.
#
# Run after every submodule bump.  `--check` verifies the generated file is in
# sync and exits non-zero on drift.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GGML="$ROOT/whisper.cpp/ggml/src"
DST="$ROOT/Sources/whisper_metal/ggml-metal.metal"

for f in "$GGML/ggml-metal/ggml-metal.metal" "$GGML/ggml-common.h" "$GGML/ggml-metal/ggml-metal-impl.h"; do
    if [ ! -f "$f" ]; then
        echo "error: $f not found — run 'git submodule update --init' first" >&2
        exit 1
    fi
done

TMP="$(mktemp -t ggml-metal-flat)"
trap 'rm -f "$TMP"' EXIT

python3 - "$GGML" "$TMP" <<'PY'
import sys, pathlib
ggml = pathlib.Path(sys.argv[1])
out  = pathlib.Path(sys.argv[2])

shader = (ggml / "ggml-metal" / "ggml-metal.metal").read_text()
inlines = {
    '#include "ggml-common.h"':      ggml / "ggml-common.h",
    '#include "ggml-metal-impl.h"':  ggml / "ggml-metal" / "ggml-metal-impl.h",
}

lines = []
for line in shader.splitlines():
    src = inlines.get(line.strip())
    if src is None:
        lines.append(line)
        continue
    lines.append(f"// ==== inlined by scripts/sync-metal-shader.sh: {src.name} ====")
    lines.append(src.read_text().rstrip("\n"))
    lines.append(f"// ==== end {src.name} ====")

missing = [k for k in inlines if not any(k in l for l in shader.splitlines())]
if missing:
    sys.exit(f"error: expected include line(s) not found in ggml-metal.metal: {missing}")

out.write_text("\n".join(lines) + "\n")
PY

if [ "${1:-}" = "--check" ]; then
    if [ -L "$DST" ]; then
        echo "error: $DST is a symlink — SwiftPM would ship a dangling link. Run $0" >&2
        exit 1
    fi
    if ! cmp -s "$TMP" "$DST"; then
        echo "error: $DST is out of sync with the submodule. Run $0" >&2
        exit 1
    fi
    echo "ggml-metal.metal is in sync"
    exit 0
fi

rm -f "$DST"
cp "$TMP" "$DST"
echo "generated ggml-metal.metal ($(wc -c < "$DST" | tr -d ' ') bytes, headers inlined)"
