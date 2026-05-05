#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-v0.4.gro"}

if [ ! -f "$FILE" ]; then
    "$ROOT/scripts/build_boot.sh"
fi

qemu-system-i386 -drive format=raw,file="$FILE"
