#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/boundaries.img"
LOG="$TMP_DIR/debug.log"
MONITOR_LOG="$TMP_DIR/monitor.log"
FS_OFFSET=122880
FS_BLOCKS=192

fail() { echo "error: $1" >&2; exit 1; }
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'

GROGAN_USER_SOURCE="$ROOT/examples/grown-alpha/user-shell.grw" \
    "$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
"$ROOT/scripts/grc0.sh" "$ROOT/examples/grown-alpha/boundary.grw" "$TMP_DIR/boundary.gwo"
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TMP_DIR/gfs2"
"$TMP_DIR/gfs2" put "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" boundary.gwo "$TMP_DIR/boundary.gwo"
"$TMP_DIR/gfs2" check "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" > /dev/null

set +e
{
    sleep 5
    for key in r u n spc b o u n d a r y dot g w o ret; do
        printf 'sendkey %s\n' "$key"
        sleep 0.08
    done
    sleep 3
    for key in e x i t ret; do
        printf 'sendkey %s\n' "$key"
        sleep 0.08
    done
    sleep 2
    printf 'quit\n'
} | timeout 30 qemu-system-x86_64 \
    -drive format=raw,file="$IMAGE" \
    -display none -monitor stdio -no-reboot -no-shutdown \
    -debugcon "file:$LOG" -global isa-debugcon.iobase=0xe9 \
    > "$MONITOR_LOG" 2>&1
status=$?
set -e
[ "$status" = 0 ] || { tail -c 4000 "$MONITOR_LOG" >&2; fail "qemu status $status"; }
grep -aF -- '-14' "$LOG" > /dev/null || fail 'cross-page user buffer was not rejected with -EFAULT'
grep -aF 'USEROK' "$LOG" > /dev/null || fail 'kernel did not recover after boundary rejection'
grep -aF 'RUN FAIL' "$LOG" > /dev/null && fail 'boundary test artifact failed to spawn'

echo 'Grogan boundaries: cross-page file_list buffer returned -EFAULT and kernel recovered'
