#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP_DIR=$(mktemp -d)
IMAGE="$TMP_DIR/modules.img"
LOG="$TMP_DIR/debug.log"
MONITOR_LOG="$TMP_DIR/monitor.log"
FS_OFFSET=122880
FS_BLOCKS=192
WAIT_AFTER_COMPILE=${WAIT_AFTER_COMPILE:-8}

fail() { echo "error: $1" >&2; exit 1; }
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'
if [ "${KEEP_TMP:-0}" = 1 ]; then
    echo "artifacts: $TMP_DIR" >&2
else
    trap 'rm -rf "$TMP_DIR"' EXIT
fi

GROGAN_USER_SOURCE="$ROOT/examples/grown-alpha/user-shell.grw" \
    "$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TMP_DIR/gfs2"
"$TMP_DIR/gfs2" put "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" module-math.grw \
    "$ROOT/examples/grown-alpha/module-math.grw"
"$TMP_DIR/gfs2" put "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" module-main.grw \
    "$ROOT/examples/grown-alpha/module-main.grw"
"$TMP_DIR/gfs2" check "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" > /dev/null

send_key() {
    printf 'sendkey %s\n' "$1"
    sleep 0.08
}

send_text() {
    local text=$1 index key
    for ((index = 0; index < ${#text}; index++)); do
        key=${text:index:1}
        case "$key" in
            ' ') key=spc ;;
            '.') key=dot ;;
            '-') key=minus ;;
        esac
        send_key "$key"
    done
    send_key ret
}

set +e
{
    sleep 5
    send_text 'grc module-main.grw module.gwo'
    sleep "$WAIT_AFTER_COMPILE"
    send_text 'run module.gwo'
    sleep 4
    send_text 'exit'
    sleep 2
    printf 'quit\n'
} | timeout 45 qemu-system-x86_64 \
    -drive format=raw,file="$IMAGE" \
    -display none \
    -monitor stdio \
    -no-reboot \
    -no-shutdown \
    -debugcon "file:$LOG" \
    -global isa-debugcon.iobase=0xe9 \
    > "$MONITOR_LOG" 2>&1
status=$?
set -e
[ "$status" = 0 ] || { tail -c 4000 "$MONITOR_LOG" >&2; fail "qemu status $status"; }
grep -aF 'GrOS user shell' "$LOG" > /dev/null || fail 'ring-3 shell banner missing'
grep -aF 'GRC FAIL' "$LOG" > /dev/null && fail 'in-OS multi-module compile failed'
grep -aF 'RUN FAIL' "$LOG" > /dev/null && fail 'in-OS multi-module run failed'
grep -aF '42' "$LOG" > /dev/null || fail 'multi-module program output missing'
grep -aF 'USEROK' "$LOG" > /dev/null || fail 'kernel recovery missing'
"$TMP_DIR/gfs2" get "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" module.gwo "$TMP_DIR/module.gwo"
[ -s "$TMP_DIR/module.gwo" ] || fail 'multi-module artifact was not persisted'

echo 'Grogan modules: two-source import compiled and executed inside GrOS'
