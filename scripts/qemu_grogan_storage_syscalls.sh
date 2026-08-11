#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/storage.img"
LOG="$TMP_DIR/debug.log"
MONITOR_LOG="$TMP_DIR/monitor.log"
FS_OFFSET=114688
FS_BLOCKS=128

fail() { echo "error: $1" >&2; exit 1; }
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'
GROGAN_USER_SOURCE="$ROOT/examples/grown-alpha/storage-smoke.grw" \
    "$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null

set +e
{
    sleep 1
    for key in r e b o o t ret; do
        printf 'sendkey %s\n' "$key"
        sleep 0.12
    done
    sleep 0.5
    printf 'quit\n'
} | timeout 15 qemu-system-x86_64 \
    -drive format=raw,file="$IMAGE" \
    -display none \
    -monitor stdio \
    -no-reboot \
    -no-shutdown \
    -debugcon "file:$LOG" \
    -global isa-debugcon.iobase=0xe9 \
    > "$MONITOR_LOG" 2>&1
STATUS=$?
set -e
[ "$STATUS" = 0 ] || { cat "$MONITOR_LOG" >&2; fail "qemu status $STATUS"; }
grep -aF 'ATAOKGFS2OK' "$LOG" > /dev/null || fail 'GFS2 mount proof missing'
grep -aF 'A' "$LOG" > /dev/null || fail 'ring-3 file syscall byte round-trip missing'

"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TMP_DIR/gfs2"
"$TMP_DIR/gfs2" check "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" > /dev/null
if "$TMP_DIR/gfs2" ls "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" | grep -F 'vm-storage-smoke.grw' > /dev/null; then
    fail 'ring-3 unlink left the temporary file on disk'
fi

echo 'Grogan storage syscalls: ring-3 create/write/read/close/unlink and GFS2 checker ok'
