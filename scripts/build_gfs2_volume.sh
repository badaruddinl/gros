#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
IMAGE=${1:?usage: build_gfs2_volume.sh <image> [offset-bytes] [blocks]}
OFFSET=${2:-65536}
BLOCKS=${3:-128}
CC=${CC:-cc}

command -v "$CC" > /dev/null 2>&1 || {
    echo "error: $CC is required to build the GFS2 image tool" >&2
    exit 1
}

TOOL=$(mktemp)
trap 'rm -f "$TOOL"' EXIT
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TOOL"
"$TOOL" format "$IMAGE" "$OFFSET" "$BLOCKS"
"$TOOL" check "$IMAGE" "$OFFSET" "$BLOCKS" > /dev/null
echo "formatted: GFS2 offset=$OFFSET bytes blocks=$BLOCKS image=$IMAGE"
