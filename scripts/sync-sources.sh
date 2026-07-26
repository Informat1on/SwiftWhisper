#!/usr/bin/env bash
# Re-create the per-file symlinks that expose whisper.cpp/ggml sources to SwiftPM.
#
# Why per-file symlinks and not just `sources: ["ggml_src/ggml.c", …]` through the
# ggml_src directory symlink: SwiftPM does not follow directory symlinks when it
# collects a target's sources — the target ends up with an empty source list and
# links to nothing.  Directory symlinks still work for headerSearchPath, which is
# why ggml_include / ggml_src / whisper_src stay.
#
# ARM kernels keep their arch/arm/ nesting because they use relative includes
# ("../../quants.h", "../../ggml-cpu-impl.h", "../../repack.h") — the matching
# headers are symlinked into the target root so those paths resolve.
#
# Run after every submodule bump, then update the `sources:` lists in Package.swift
# if upstream added or removed files.  `--check` verifies nothing dangles.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GGML="whisper.cpp/ggml/src"
WSRC="whisper.cpp/src"

CPP_ROOT="$ROOT/Sources/whisper_cpp"
METAL_ROOT="$ROOT/Sources/whisper_metal"

# target-root:destination-relative-path:source-path-relative-to-repository-root
FILES=(
    "metal:ggml-metal.cpp:$GGML/ggml-metal/ggml-metal.cpp"
    "metal:ggml-metal-common.cpp:$GGML/ggml-metal/ggml-metal-common.cpp"
    "metal:ggml-metal-context.m:$GGML/ggml-metal/ggml-metal-context.m"
    "metal:ggml-metal-device.m:$GGML/ggml-metal/ggml-metal-device.m"
    "metal:ggml-metal-device.cpp:$GGML/ggml-metal/ggml-metal-device.cpp"
    "metal:ggml-metal-ops.cpp:$GGML/ggml-metal/ggml-metal-ops.cpp"
)

CPP_FILES=(
    "whisper.cpp:$WSRC/whisper.cpp"
    "whisper-arch.h:$WSRC/whisper-arch.h"

    "ggml.c:$GGML/ggml.c"
    "ggml.cpp:$GGML/ggml.cpp"
    "ggml-alloc.c:$GGML/ggml-alloc.c"
    "ggml-backend.cpp:$GGML/ggml-backend.cpp"
    "ggml-backend-meta.cpp:$GGML/ggml-backend-meta.cpp"
    "ggml-backend-reg.cpp:$GGML/ggml-backend-reg.cpp"
    "ggml-backend-dl.cpp:$GGML/ggml-backend-dl.cpp"
    "ggml-opt.cpp:$GGML/ggml-opt.cpp"
    "ggml-quants.c:$GGML/ggml-quants.c"
    "ggml-threading.cpp:$GGML/ggml-threading.cpp"
    "gguf.cpp:$GGML/gguf.cpp"

    "ggml-cpu.c:$GGML/ggml-cpu/ggml-cpu.c"
    "ggml-cpu.cpp:$GGML/ggml-cpu/ggml-cpu.cpp"
    "binary-ops.cpp:$GGML/ggml-cpu/binary-ops.cpp"
    "unary-ops.cpp:$GGML/ggml-cpu/unary-ops.cpp"
    "ops.cpp:$GGML/ggml-cpu/ops.cpp"
    "quants.c:$GGML/ggml-cpu/quants.c"
    "repack.cpp:$GGML/ggml-cpu/repack.cpp"
    "traits.cpp:$GGML/ggml-cpu/traits.cpp"
    "vec.cpp:$GGML/ggml-cpu/vec.cpp"
    "hbm.cpp:$GGML/ggml-cpu/hbm.cpp"

    # headers reached from arch/arm via "../../"
    "quants.h:$GGML/ggml-cpu/quants.h"
    "repack.h:$GGML/ggml-cpu/repack.h"
    "ggml-cpu-impl.h:$GGML/ggml-cpu/ggml-cpu-impl.h"

    "arch/arm/quants.c:$GGML/ggml-cpu/arch/arm/quants.c"
    "arch/arm/repack.cpp:$GGML/ggml-cpu/arch/arm/repack.cpp"
)

for entry in "${CPP_FILES[@]}"; do
    FILES+=("cpp:$entry")
done

check=false
[ "${1:-}" = "--check" ] && check=true

status=0
for entry in "${FILES[@]}"; do
    root_key="${entry%%:*}"
    rest="${entry#*:}"
    dst_rel="${rest%%:*}"
    src_rel="${rest#*:}"
    if [ "$root_key" = "metal" ]; then
        dst="$METAL_ROOT/$dst_rel"
    else
        dst="$CPP_ROOT/$dst_rel"
    fi
    src="$ROOT/$src_rel"

    if [ ! -f "$src" ]; then
        echo "error: missing upstream source $src_rel — is the submodule checked out?" >&2
        status=1
        continue
    fi

    # depth of dst below Sources/<target> → number of "../" to reach the repo root
    depth=$(( $(printf '%s' "$dst_rel" | tr -cd '/' | wc -c) + 2 ))
    prefix=""
    for _ in $(seq 1 "$depth"); do prefix="../$prefix"; done
    want="$prefix$src_rel"

    if $check; then
        if [ ! -e "$dst" ]; then
            echo "error: $dst_rel is missing or dangling — run $0" >&2
            status=1
        elif [ "$(readlink "$dst")" != "$want" ]; then
            # a valid link pointing at the wrong upstream file must not pass
            echo "error: $dst_rel points at $(readlink "$dst"), expected $want — run $0" >&2
            status=1
        fi
        continue
    fi

    mkdir -p "$(dirname "$dst")"
    ln -sfn "$want" "$dst"
done

if $check; then
    [ "$status" -eq 0 ] && echo "whisper_cpp source symlinks are in sync"
    exit "$status"
fi

echo "linked ${#FILES[@]} sources into Sources/whisper_cpp/ and Sources/whisper_metal/"
