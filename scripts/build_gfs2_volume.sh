#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
IMAGE=${1:?usage: build_gfs2_volume.sh <image> [offset-bytes] [blocks]}
OFFSET=${2:-65536}
BLOCKS=${3:-128}
CC=${CC:-cc}
SEED_COMPILER=${GFS2_SEED_COMPILER:-}
SEED_SOURCE=${GFS2_SEED_SOURCE:-}

command -v "$CC" > /dev/null 2>&1 || {
    echo "error: $CC is required to build the GFS2 image tool" >&2
    exit 1
}

TOOL=$(mktemp)
trap 'rm -f "$TOOL"' EXIT
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TOOL"
"$TOOL" format "$IMAGE" "$OFFSET" "$BLOCKS"
if [ -n "$SEED_COMPILER" ]; then
    [ -f "$SEED_COMPILER" ] || { echo "error: compiler seed not found: $SEED_COMPILER" >&2; exit 1; }
    "$TOOL" put "$IMAGE" "$OFFSET" "$BLOCKS" grc1.gwo "$SEED_COMPILER"
fi
if [ -n "$SEED_SOURCE" ]; then
    [ -f "$SEED_SOURCE" ] || { echo "error: source seed not found: $SEED_SOURCE" >&2; exit 1; }
    "$TOOL" put "$IMAGE" "$OFFSET" "$BLOCKS" grc1.grw "$SEED_SOURCE"
fi
"$TOOL" check "$IMAGE" "$OFFSET" "$BLOCKS" > /dev/null
echo "formatted: GFS2 offset=$OFFSET bytes blocks=$BLOCKS image=$IMAGE"
