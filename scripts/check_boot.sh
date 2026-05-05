#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-v0.3.gro"}

if [ ! -f "$FILE" ]; then
    echo "error: file not found: $FILE"
    echo "run: ./scripts/build_boot.sh"
    exit 1
fi

SIZE=$(wc -c < "$FILE" | tr -d ' ')
SIG=$(tail -c 2 "$FILE" | od -An -tx1 | tr -d ' \n')

echo "file     : $FILE"
echo "size     : $SIZE bytes"
echo "signature: $SIG"

if [ "$SIZE" != "512" ]; then
    echo "error: boot sector must be 512 bytes"
    exit 1
fi

if [ "$SIG" != "55aa" ]; then
    echo "error: boot signature must be 55aa"
    exit 1
fi

echo "ok: valid GrBoot sector"
