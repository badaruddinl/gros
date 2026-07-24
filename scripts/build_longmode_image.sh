#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${1:-"$ROOT/build/gros-longmode.img"}
command -v nasm > /dev/null 2>&1 || { echo 'error: nasm is required' >&2; exit 1; }
mkdir -p "$(dirname -- "$OUT")"
nasm -f bin "$ROOT/kernel/longmode_boot.asm" -o "$OUT"
[ "$(wc -c < "$OUT" | tr -d ' ')" = 16896 ] || { echo 'error: long-mode image must be 16896 bytes' >&2; exit 1; }
echo "built: $OUT"
