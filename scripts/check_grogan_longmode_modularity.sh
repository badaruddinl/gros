#!/usr/bin/env bash
set -euo pipefail

# The modularization commit is intentionally compared with its direct parent:
# the parent is the recorded monolithic source, while the current commit uses
# ordered NASM includes.  Both sides are rebuilt from isolated source trees and
# the complete kernel/image bytes must match exactly.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KERNEL_BYTES=117248
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
fail() { echo "error: $1" >&2; exit 1; }

git -C "$ROOT" rev-parse --verify HEAD^ > /dev/null 2>&1 || fail 'modularity check requires a parent commit'
PARENT="$TMP_DIR/parent"
mkdir -p "$PARENT"
git -C "$ROOT" archive --format=tar HEAD^ | tar -xf - -C "$PARENT"

(cd "$PARENT" && bash scripts/build_longmode_image.sh "$TMP_DIR/parent.img" > /dev/null)
bash "$ROOT/scripts/build_longmode_image.sh" "$TMP_DIR/current.img" > /dev/null

dd if="$TMP_DIR/parent.img" bs=1 count="$KERNEL_BYTES" status=none > "$TMP_DIR/parent.kernel"
dd if="$TMP_DIR/current.img" bs=1 count="$KERNEL_BYTES" status=none > "$TMP_DIR/current.kernel"
cmp -s "$TMP_DIR/parent.kernel" "$TMP_DIR/current.kernel" || fail 'modular kernel bytes differ from the monolithic parent'
cmp -s "$TMP_DIR/parent.img" "$TMP_DIR/current.img" || fail 'modular image bytes differ from the monolithic parent'

grep -F '%include "kernel/longmode_boot_ata_wait.inc"' "$ROOT/kernel/longmode_boot.asm" > /dev/null || \
    fail 'ATA wait implementation is not included from its subsystem file'
echo 'Grogan NASM modularity: ordered ATA include is byte-identical to the monolithic parent kernel and image'
