#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/large.img"
LOG="$TMP_DIR/debug.log"
MONITOR_LOG="$TMP_DIR/monitor.log"

fail() { echo "error: $1" >&2; exit 1; }
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'
GROGAN_USER_SOURCE="$ROOT/examples/grown-alpha/storage-large.grw" \
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
} | timeout 20 qemu-system-x86_64 \
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
grep -aF '1024' "$LOG" > /dev/null || fail 'multi-block ring-3 round-trip missing'

"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TMP_DIR/gfs2"
"$TMP_DIR/gfs2" check "$IMAGE" 65536 128 > /dev/null
if "$TMP_DIR/gfs2" ls "$IMAGE" 65536 128 | grep -F 'vm-storage-large.grw' > /dev/null; then
    fail 'multi-block unlink left the temporary file on disk'
fi

echo 'Grogan large file: ring-3 multi-block write/read/unlink and GFS2 checker ok'
