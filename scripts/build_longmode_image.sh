#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${1:-"$ROOT/build/gros-longmode.img"}
KERNEL_BYTES=59904
FS_START_LBA=128
FS_BLOCKS=128
USER_SOURCE=${GROGAN_USER_SOURCE:-"$ROOT/examples/grown-alpha/hello.grw"}
command -v nasm > /dev/null 2>&1 || { echo 'error: nasm is required' >&2; exit 1; }
mkdir -p "$(dirname -- "$OUT")"
mkdir -p "$ROOT/build/generated"
"$ROOT/scripts/grc0.sh" \
    "$USER_SOURCE" \
    "$ROOT/build/generated/grogan-user.gwo"
"$ROOT/scripts/grc0.sh" \
    "$ROOT/examples/grown-alpha/hello.grw" \
    "$ROOT/build/generated/grogan-helper.gwo"
cd "$ROOT"
nasm -f bin "$ROOT/kernel/longmode_boot.asm" -o "$OUT"
[ "$(wc -c < "$OUT" | tr -d ' ')" = "$KERNEL_BYTES" ] || { echo "error: long-mode kernel must be $KERNEL_BYTES bytes" >&2; exit 1; }
# The BIOS transfer covers only the boot sector plus KERNEL_LOAD_SECTORS.  The
# remaining sectors are a real disk surface for the GFS2 block layer; keeping
# it in the same raw image lets ATA persistence survive a QEMU reboot.
truncate -s "$((512 * (FS_START_LBA + FS_BLOCKS)))" "$OUT"
"$ROOT/scripts/build_gfs2_volume.sh" "$OUT" "$((512 * FS_START_LBA))" "$FS_BLOCKS" > /dev/null
echo "built: $OUT"
