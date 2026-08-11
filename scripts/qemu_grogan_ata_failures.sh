#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/short-disk.img"
LOG="$TMP_DIR/debug.log"
MONITOR_LOG="$TMP_DIR/monitor.log"
FS_START_LBA=240

fail() { echo "error: $1" >&2; exit 1; }
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'

"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
# Leave a valid boot transfer but remove the first sector of the declared GFS2
# volume.  IDENTIFY therefore reports a capacity at the filesystem boundary;
# ata_block_read must reject it immediately rather than polling forever.
truncate -s "$((FS_START_LBA * 512))" "$IMAGE"

set +e
timeout 8 qemu-system-x86_64 \
    -drive format=raw,file="$IMAGE" \
    -display none -no-reboot -no-shutdown \
    -debugcon "file:$LOG" -global isa-debugcon.iobase=0xe9 \
    > "$MONITOR_LOG" 2>&1
status=$?
set -e
[ "$status" = 124 ] || { tail -c 4000 "$MONITOR_LOG" >&2; fail "qemu status $status"; }
grep -aF 'ATAFAIL' "$LOG" > /dev/null || fail 'short ATA capacity was not rejected'
if grep -aF 'ATAOK' "$LOG" > /dev/null; then
    fail 'short ATA capacity was reported as healthy'
fi

echo 'Grogan ATA failures: out-of-range disk capacity failed fast with bounded boot behavior'
