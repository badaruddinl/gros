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

run_fault() {
    local name=$1 define=$2 marker=$3 image="$TMP_DIR/$1.img" log="$TMP_DIR/$1.log" monitor="$TMP_DIR/$1.monitor"
    LONGMODE_NASM_DEFINE="$define" \
        "$ROOT/scripts/build_longmode_image.sh" "$image" > /dev/null
    set +e
    timeout 8 qemu-system-x86_64 \
        -drive format=raw,file="$image" \
        -display none -no-reboot -no-shutdown \
        -debugcon "file:$log" -global isa-debugcon.iobase=0xe9 \
        > "$monitor" 2>&1
    local status=$?
    set -e
    [ "$status" = 124 ] || { tail -c 4000 "$monitor" >&2; fail "$name qemu status $status"; }
    grep -aF 'ATAFAIL' "$log" > /dev/null || fail "$name did not report ATAFAIL"
    grep -aF "$marker" "$log" > /dev/null || fail "$name did not exercise $marker"
    if grep -aF 'ATAOK' "$log" > /dev/null; then
        fail "$name reported ATAOK"
    fi
}

run_fault err ATA_TEST_FAULT=1 ATAERR
run_fault timeout ATA_TEST_FAULT=2 ATATMO

# Leave a valid boot transfer but remove the first sector of the declared GFS2
# volume. IDENTIFY therefore reports a capacity at the filesystem boundary;
# ata_block_read must reject it immediately rather than polling forever.
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
truncate -s "$((FS_START_LBA * 512))" "$IMAGE"
set +e
timeout 8 qemu-system-x86_64 \
    -drive format=raw,file="$IMAGE" \
    -display none -no-reboot -no-shutdown \
    -debugcon "file:$LOG" -global isa-debugcon.iobase=0xe9 \
    > "$MONITOR_LOG" 2>&1
status=$?
set -e
[ "$status" = 124 ] || { tail -c 4000 "$MONITOR_LOG" >&2; fail "range qemu status $status"; }
grep -aF 'ATAFAIL' "$LOG" > /dev/null || fail 'short ATA capacity was not rejected'
grep -aF 'ATARANGE' "$LOG" > /dev/null || fail 'short ATA capacity did not exercise the range branch'
if grep -aF 'ATAOK' "$LOG" > /dev/null; then
    fail 'short ATA capacity was reported as healthy'
fi

echo 'Grogan ATA failures: ERR, timeout, and out-of-range capacity fail fast with bounded boot behavior'
