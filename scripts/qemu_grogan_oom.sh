#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/oom.img"
LOG="$TMP_DIR/debug.log"
MONITOR_LOG="$TMP_DIR/monitor.log"
FS_OFFSET=122880
FS_BLOCKS=192

fail() { echo "error: $1" >&2; exit 1; }
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'
GROGAN_USER_SOURCE="$ROOT/examples/grown-alpha/user-shell.grw" \
    "$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
"$ROOT/scripts/grc0.sh" "$ROOT/examples/grown-alpha/oom.grw" "$TMP_DIR/oom.gwo"
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TMP_DIR/gfs2"
"$TMP_DIR/gfs2" put "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" oom.gwo "$TMP_DIR/oom.gwo"
"$TMP_DIR/gfs2" check "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" > /dev/null

set +e
{
    sleep 5
    for key in r u n spc o o m dot g w o ret; do
        printf 'sendkey %s\n' "$key"
        sleep 0.08
    done
    sleep 10
    for key in e x i t ret; do
        printf 'sendkey %s\n' "$key"
        sleep 0.08
    done
    sleep 2
    printf 'quit\n'
} | timeout 35 qemu-system-x86_64 \
    -drive format=raw,file="$IMAGE" \
    -display none -monitor stdio -no-reboot -no-shutdown \
    -debugcon "file:$LOG" -global isa-debugcon.iobase=0xe9 \
    > "$MONITOR_LOG" 2>&1
status=$?
set -e
[ "$status" = 0 ] || { tail -c 4000 "$MONITOR_LOG" >&2; fail "qemu status $status"; }
grep -aF -- '-12' "$LOG" > /dev/null || fail 'ring-3 allocator did not report -ENOMEM'
grep -aF 'USEROK' "$LOG" > /dev/null || fail 'kernel failed during ring-3 OOM'
grep -aF 'RUN FAIL' "$LOG" > /dev/null && fail 'OOM program spawn failed'

echo 'Grogan OOM: process-owned memory exhaustion returned -ENOMEM and recovered'
