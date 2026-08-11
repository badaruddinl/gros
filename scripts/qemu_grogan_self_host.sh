#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
if [ "${KEEP_TMP:-0}" = 1 ]; then
    TMP_DIR="$ROOT/build/self-host-qemu"
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"
    echo "artifacts: $TMP_DIR" >&2
else
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
fi
IMAGE="$TMP_DIR/self-host.img"
LOG="$TMP_DIR/debug.log"
MONITOR_LOG="$TMP_DIR/monitor.log"
FS_OFFSET=114688
FS_BLOCKS=128
WAIT_AFTER_B=${WAIT_AFTER_B:-70}
WAIT_AFTER_X=${WAIT_AFTER_X:-30}
QEMU_TIMEOUT=${QEMU_TIMEOUT:-115}

fail() { echo "error: $1" >&2; exit 1; }
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'

GROGAN_USER_SOURCE="$ROOT/examples/grown-alpha/user-shell.grw" \
    "$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null

set +e
{
    sleep 5
    printf 'sendkey b\n'
    sleep "$WAIT_AFTER_B"
    printf 'sendkey x\n'
    sleep "$WAIT_AFTER_X"
    printf 'quit\n'
} | timeout "$QEMU_TIMEOUT" qemu-system-x86_64 \
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
grep -aF 'COMPILE OK' "$LOG" > /dev/null || { tail -c 4000 "$LOG" >&2; fail 'in-OS compiler did not complete'; }
grep -aF 'RUN OK' "$LOG" > /dev/null || { tail -c 4000 "$LOG" >&2; fail 'in-OS compiled artifact did not run'; }

"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TMP_DIR/gfs2"
"$TMP_DIR/gfs2" check "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" > /dev/null
"$TMP_DIR/gfs2" ls "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" | grep -F 'grc2.gwo' > /dev/null || \
    fail 'compiled artifact was not persisted in GFS2'

echo 'Grogan self-host: ring-3 compile/run and persistent grc2.gwo verified'
