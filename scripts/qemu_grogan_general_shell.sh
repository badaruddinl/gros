#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP_DIR=$(mktemp -d)
if [ "${KEEP_TMP:-0}" = 1 ]; then
    echo "artifacts: $TMP_DIR" >&2
else
    trap 'rm -rf "$TMP_DIR"' EXIT
fi
IMAGE="$TMP_DIR/general-shell.img"
LOG="$TMP_DIR/debug.log"
MONITOR_LOG="$TMP_DIR/monitor.log"
FS_OFFSET=122880
FS_BLOCKS=192
WAIT_AFTER_COMPILE=${WAIT_AFTER_COMPILE:-25}
WAIT_AFTER_RUN=${WAIT_AFTER_RUN:-15}

fail() { echo "error: $1" >&2; exit 1; }
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'

GROGAN_USER_SOURCE="$ROOT/examples/grown-alpha/user-shell.grw" \
    "$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null

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
            '/') key=slash ;;
        esac
        send_key "$key"
    done
    send_key ret
}

set +e
{
    sleep 5
    send_text 'help'
    send_text 'ls'
    send_text 'grc grc1.grw test.gwo'
    sleep "$WAIT_AFTER_COMPILE"
    send_text 'run test.gwo'
    sleep "$WAIT_AFTER_RUN"
    send_text 'exit'
    sleep 2
    printf 'quit\n'
} | timeout 55 qemu-system-x86_64 \
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
grep -aF 'ls cat rm write edit grc run [args] exit' "$LOG" > /dev/null || fail 'general help output missing'
grep -aF 'grc1.grw' "$LOG" > /dev/null || fail 'root directory listing missing'
grep -aF 'OK' "$LOG" > /dev/null || fail 'in-OS general compile did not complete'
grep -aF 'USEROK' "$LOG" > /dev/null || fail 'general shell did not return control to the kernel'

"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TMP_DIR/gfs2"
"$TMP_DIR/gfs2" check "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" > /dev/null
"$TMP_DIR/gfs2" ls "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" | grep -F 'test.gwo' > /dev/null || \
    fail 'general compiler artifact was not persisted'

echo 'Grogan general shell: command parsing, listing, arbitrary compile/run, and persistence verified'
