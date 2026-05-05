#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/boot/grboot_v0_3.gr"
OUT="$ROOT/build/gros-v0.3.gro"

mkdir -p "$ROOT/build"
rm -f "$OUT"

"$ROOT/scripts/grraw.sh" "$SRC" "$OUT"

SIZE=$(wc -c < "$OUT" | tr -d ' ')

if [ "$SIZE" != "512" ]; then
    echo "error: boot sector must be 512 bytes, got $SIZE"
    exit 1
fi

FINAL_SIZE=$(wc -c < "$OUT" | tr -d ' ')
echo "built: $OUT"
echo "size : $FINAL_SIZE bytes"
