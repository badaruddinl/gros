#!/usr/bin/env bash
set -euo pipefail

# Exercise the complete ring-3 development loop repeatedly on one persistent
# disk.  Each iteration starts a fresh QEMU boot, writes and saves a file
# through the editor, compiles and runs the Grown compiler, removes its
# artifacts, and shuts down cleanly.  The default is the Alpha release
# requirement (100 cycles); smaller CYCLES values are useful for local work.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
CYCLES=${CYCLES:-100}
FS_OFFSET=122880
FS_BLOCKS=192
SEND_DELAY=${SEND_DELAY:-0.01}
BOOT_WAIT=${BOOT_WAIT:-2}
COMPILE_WAIT=${COMPILE_WAIT:-6}
QEMU_TIMEOUT=${QEMU_TIMEOUT:-3600}
TMP_DIR=$(mktemp -d)
IMAGE="$TMP_DIR/reliability.img"
LOG="$TMP_DIR/debug.log"

fail() { echo "error: $1" >&2; exit 1; }
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'
[[ "$CYCLES" =~ ^[1-9][0-9]*$ ]] || fail 'CYCLES must be a positive integer'

if [ "${KEEP_TMP:-0}" = 1 ]; then
    echo "artifacts: $TMP_DIR" >&2
else
    trap 'rm -rf "$TMP_DIR"' EXIT
fi

GROGAN_USER_SOURCE="$ROOT/examples/grown-alpha/user-shell.grw" \
    "$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null

send_key() {
    printf 'sendkey %s\n' "$1"
    sleep "$SEND_DELAY"
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
: > "$LOG"
for ((cycle = 1; cycle <= CYCLES; cycle++)); do
    cycle_log="$TMP_DIR/debug-$cycle.log"
    cycle_monitor="$TMP_DIR/monitor-$cycle.log"
    # This small file keeps the editor test independent from the large
    # compiler source while still exercising open, save, truncate, and close
    # on every independent clean boot.
    set +e
    {
        sleep "$BOOT_WAIT"
        send_text 'write cycle.txt stable'
        send_text 'edit cycle.txt'
        send_text 'delete'
        send_text 'save'
        send_text 'grc grc1.grw cycle.gwo'
        sleep "$COMPILE_WAIT"
        send_text 'run cycle.gwo grc1.grw cycle-out.gwo'
        sleep "$COMPILE_WAIT"
        send_text 'rm cycle.gwo'
        send_text 'rm cycle-out.gwo'
        send_text 'rm cycle.txt'
        send_text 'exit'
        sleep 2
        printf 'quit\n'
    } | timeout "$QEMU_TIMEOUT" qemu-system-x86_64 \
        -drive format=raw,file="$IMAGE" \
        -display none \
        -monitor stdio \
        -no-reboot \
        -no-shutdown \
        -debugcon "file:$cycle_log" \
        -global isa-debugcon.iobase=0xe9 \
        > "$cycle_monitor" 2>&1
    status=$?
    set -e
    [ "$status" = 0 ] || { tail -c 6000 "$cycle_monitor" >&2; fail "qemu cycle $cycle status $status"; }
    cat "$cycle_log" >> "$LOG"
    grep -aF 'SAVE OK' "$cycle_log" > /dev/null || fail "editor save missing on cycle $cycle"
    grep -aF 'USEROK' "$cycle_log" > /dev/null || fail "kernel recovery missing on cycle $cycle"
    compile_runs=$(grep -ao 'GWO2OK' "$cycle_log" | wc -l | tr -d ' ')
    [ "$compile_runs" -ge 2 ] || fail "compile/run success missing on cycle $cycle"
    grep -aF 'GRC FAIL' "$cycle_log" > /dev/null && fail "compiler failed on cycle $cycle"
    grep -aF 'RUN FAIL' "$cycle_log" > /dev/null && fail "compiled program failed on cycle $cycle"
done

count=$(grep -ao 'SAVE OK' "$LOG" | wc -l | tr -d ' ')
[ "$count" -ge "$CYCLES" ] || fail "editor save count $count/$CYCLES"
count=$(grep -ao 'USEROK' "$LOG" | wc -l | tr -d ' ')
[ "$count" -ge "$CYCLES" ] || fail "clean boot recovery count $count/$CYCLES"
count=$(grep -ao 'OK' "$LOG" | wc -l | tr -d ' ')
[ "$count" -ge "$((CYCLES * 2))" ] || fail "compile/run success count $count/$((CYCLES * 2))"
for marker in 'WRITE FAIL' 'SAVE FAIL' 'EDITOR ENOSPC' 'GRC FAIL' 'RUN FAIL' 'LS FAIL'; do
    if grep -aF "$marker" "$LOG" > /dev/null; then
        fail "reliability transcript contains $marker"
    fi
done

"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TMP_DIR/gfs2"
"$TMP_DIR/gfs2" check "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" > /dev/null
listing=$("$TMP_DIR/gfs2" ls "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS")
if printf '%s\n' "$listing" | grep -E '^(cycle\.txt|cycle\.gwo|cycle-out\.gwo)$' > /dev/null; then
    fail 'reliability artifacts were not removed'
fi

echo "Grogan reliability: $CYCLES clean-boot editor/compile/run/reboot cycles and GFS2 check passed"
