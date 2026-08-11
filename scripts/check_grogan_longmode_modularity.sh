#!/usr/bin/env bash
set -euo pipefail

# The first modularization commit is compared with its direct parent: the
# parent is the recorded monolithic source, while the current commit uses
# ordered NASM includes.  Later hardening commits legitimately change runtime
# bytes; once the parent is already modular, prove deterministic assembly from
# two isolated current builds instead of comparing unrelated semantics.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KERNEL_BYTES=117248
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
fail() { echo "error: $1" >&2; exit 1; }

git -C "$ROOT" rev-parse --verify HEAD^ > /dev/null 2>&1 || fail 'modularity check requires a parent commit'
PARENT_SOURCE=$(git -C "$ROOT" show HEAD^:kernel/longmode_boot.asm)
if grep -F '%include "kernel/entry.asm"' <<< "$PARENT_SOURCE" > /dev/null; then
    bash "$ROOT/scripts/build_longmode_image.sh" "$TMP_DIR/current-a.img" > /dev/null
    bash "$ROOT/scripts/build_longmode_image.sh" "$TMP_DIR/current-b.img" > /dev/null
    cmp -s "$TMP_DIR/current-a.img" "$TMP_DIR/current-b.img" || fail 'modular image is not deterministic'
else
    PARENT="$TMP_DIR/parent"
    mkdir -p "$PARENT"
    git -C "$ROOT" archive --format=tar HEAD^ | tar -xf - -C "$PARENT"
    (cd "$PARENT" && bash scripts/build_longmode_image.sh "$TMP_DIR/parent.img" > /dev/null)
    bash "$ROOT/scripts/build_longmode_image.sh" "$TMP_DIR/current.img" > /dev/null
    dd if="$TMP_DIR/parent.img" bs=1 count="$KERNEL_BYTES" status=none > "$TMP_DIR/parent.kernel"
    dd if="$TMP_DIR/current.img" bs=1 count="$KERNEL_BYTES" status=none > "$TMP_DIR/current.kernel"
    cmp -s "$TMP_DIR/parent.kernel" "$TMP_DIR/current.kernel" || fail 'modular kernel bytes differ from the monolithic parent'
    cmp -s "$TMP_DIR/parent.img" "$TMP_DIR/current.img" || fail 'modular image bytes differ from the monolithic parent'
fi

grep -F '%include "kernel/drivers/ata.asm"' "$ROOT/kernel/longmode_boot.asm" > /dev/null || \
    fail 'ATA driver is not included from the kernel driver tree'
grep -F '%include "kernel/longmode_boot_ata_wait.inc"' "$ROOT/kernel/drivers/ata.asm" > /dev/null || \
    fail 'ATA wait implementation is not included from its subsystem file'
echo 'Grogan NASM modularity: ordered subsystem includes are deterministic; refactor parent identity remains gated'
