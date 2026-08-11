#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/fault.img"
FAULT_GWO="$TMP_DIR/fault.gwo"
LOG="$TMP_DIR/debug.log"
OUT="$TMP_DIR/qemu.out"

command -v qemu-system-x86_64 > /dev/null 2>&1 || { echo 'error: qemu-system-x86_64 is required' >&2; exit 1; }

# GWO1 native payload: read the deliberately unmapped guard page at 0x401000.
# Both independently loaded processes take the fault; the kernel reaps each
# process and reaches the normal shell path instead of fail-stopping.
printf '%b' '\x47\x57\x4f\x31\x01\x00\x00\x00\x18\x00\x00\x00\x08\x00\x00\x00\x00\x00\x00\x00\x4c\x01\x00\x00\x48\x8b\x04\x25\x00\x10\x40\x00' > "$FAULT_GWO"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
OFFSET=$(grep -aob 'GWO1' "$IMAGE" | tail -n 1 | cut -d: -f1)
[ -n "$OFFSET" ] || { echo 'error: embedded GWO1 payload not found' >&2; exit 1; }
dd if="$FAULT_GWO" of="$IMAGE" bs=1 seek="$OFFSET" conv=notrunc status=none

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
