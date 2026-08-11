#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/fault.img"
LOG="$TMP_DIR/debug.log"
OUT="$TMP_DIR/qemu.out"

command -v qemu-system-x86_64 > /dev/null 2>&1 || { echo 'error: qemu-system-x86_64 is required' >&2; exit 1; }

# This is a fault-injection fixture, not a production executable.  The image
# normally copies the fixed GrVM entry after the VMP2 marker.  Replacing its
# first instruction with a read from the deliberately unmapped guard page
# proves that both independent ring-3 processes are terminated without
# converting a user fault into a kernel halt.
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
OFFSET=$(grep -aob 'VMP2' "$IMAGE" | tail -n 1 | cut -d: -f1)
[ -n "$OFFSET" ] || { echo 'error: VM entry marker not found' >&2; exit 1; }
printf '%b' '\x48\x8b\x04\x25\x00\x20\x40\x00' | dd of="$IMAGE" bs=1 seek="$((OFFSET + 4))" conv=notrunc status=none

set +e
timeout 8 qemu-system-x86_64 \
    -drive format=raw,file="$IMAGE" \
    -display none -no-reboot -no-shutdown \
    -debugcon "file:$LOG" -global isa-debugcon.iobase=0xe9 \
    > "$OUT" 2>&1
STATUS=$?
set -e
[ "$STATUS" = 124 ] || { cat "$OUT" >&2; echo "error: qemu status $STATUS" >&2; exit 1; }
PF_COUNT=$(grep -o 'PF' "$LOG" | wc -l | tr -d ' ')
[ "$PF_COUNT" -ge 2 ] || { echo 'error: both user faults were not isolated' >&2; exit 1; }
grep -F 'USEROK' "$LOG" > /dev/null || { echo 'error: kernel did not recover to shell after user faults' >&2; exit 1; }
echo 'Grogan processes: two guard-page faults terminated only their processes'
