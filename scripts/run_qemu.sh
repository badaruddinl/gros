#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-v0.5.gwo"}

if [ ! -f "$FILE" ]; then
    "$ROOT/scripts/build_boot.sh"
fi

qemu-system-i386 -drive format=raw,file="$FILE"
