#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/user-shell.img"
LOG="$TMP_DIR/debug.log"
MONITOR_LOG="$TMP_DIR/monitor.log"
FS_OFFSET=122880
FS_BLOCKS=192

fail() { echo "error: $1" >&2; exit 1; }
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'
GROGAN_USER_SOURCE="$ROOT/examples/grown-alpha/user-shell.grw" \
    "$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null

set +e
{
    sleep 1.5
    for key in l s; do
        printf 'sendkey %s\n' "$key"
        sleep 0.15
    done
    sleep 0.5
    printf 'sendkey s\n'
    sleep 0.6
    printf 'sendkey c\n'
    sleep 0.6
    for key in r m; do
        printf 'sendkey %s\n' "$key"
        sleep 0.15
    done
    sleep 0.6
    for key in r e; do
        printf 'sendkey %s\n' "$key"
        sleep 0.15
    done
    sleep 0.7
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

grep -aF 'GrOS user shell' "$LOG" > /dev/null || fail 'ring-3 shell banner missing'
grep -aF 'hello.grw' "$LOG" > /dev/null || fail 'ring-3 ls output missing'
grep -aF 'SAVE OK' "$LOG" > /dev/null || fail 'ring-3 save output missing'
grep -aF 'print_i32(28);' "$LOG" > /dev/null || fail 'ring-3 cat output missing'
grep -aF 'RM OK' "$LOG" > /dev/null || fail 'ring-3 rm output missing'
grep -aF 'USEROK' "$LOG" > /dev/null || fail 'ring-3 shell did not return control to the kernel'

"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TMP_DIR/gfs2"
"$TMP_DIR/gfs2" check "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" > /dev/null
if "$TMP_DIR/gfs2" ls "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" | grep -F 'hello.grw' > /dev/null; then
    fail 'ring-3 rm left hello.grw on disk'
fi

echo 'Grogan ring-3 shell: ls/cat/save/rm and persistent GFS2 checker ok'
