#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-longmode.img"}

fail() {
    echo "error: $1" >&2
    exit 1
}

command -v qemu-system-x86_64 > /dev/null 2>&1 || fail "qemu-system-x86_64 is required"
[ -f "$FILE" ] || fail "file not found: $FILE"

DEBUG_LOG=$(mktemp)
MONITOR_LOG=$(mktemp)
cleanup() {
    if [ "${GROGAN_QEMU_KEEP_LOG:-0}" = 1 ]; then
        echo "debug log: $DEBUG_LOG" >&2
        echo "monitor log: $MONITOR_LOG" >&2
        return
    fi
    rm -f "$DEBUG_LOG" "$MONITOR_LOG"
}
trap cleanup EXIT

send_word() {
    local word=$1
    local key
    for ((index = 0; index < ${#word}; index++)); do
        key=${word:index:1}
        printf 'sendkey %s\n' "$key"
        sleep 0.08
    done
    printf 'sendkey ret\n'
    sleep 0.15
}

set +e
{
    sleep 1
    send_word help
    send_word ls
    send_word cat
    send_word mem
    send_word tasks
    send_word reboot
    sleep 0.5
    printf 'quit\n'
} | timeout 15 qemu-system-x86_64 \
    -drive format=raw,file="$FILE" \
    -display none \
    -monitor stdio \
    -no-reboot \
    -no-shutdown \
    -debugcon "file:$DEBUG_LOG" \
    -global isa-debugcon.iobase=0xe9 \
    > "$MONITOR_LOG" 2>&1
STATUS=$?
set -e
[ "$STATUS" = 0 ] || { cat "$MONITOR_LOG" >&2; fail "qemu status $STATUS"; }

require_text() {
    local text=$1
    local name=$2
    grep -aF "$text" "$DEBUG_LOG" > /dev/null || fail "missing shell transcript: $name"
}

require_text 'LM64IDTGRO64PGM2PMEMF1F2HEAPT1T2FSOK' 'bootstrap'
require_text 'SCFGGWO2OK' 'syscall/GWO2 user boundary'
require_text '28' 'GWO2 VM output'
require_text 'IRQ' 'timer IRQ'
require_text 'P1' 'preemptive task-one context'
require_text 'P2' 'preemptive task-two context'
require_text $'help\r\nhelp ls cat mem tasks reboot\r\n' 'help response'
require_text $'ls\r\nINIT\r\n' 'ls response'
require_text $'cat\r\nINIT: GRFS\r\n' 'cat response'
require_text $'mem\r\nFRAMES HEAP PAGES\r\n' 'mem response'
require_text $'tasks\r\nT1 T2\r\n' 'tasks response'
require_text $'reboot\r\nREBOOT\r\n' 'reboot response'
require_text 'EX06' 'exception proof'

echo 'Grogan shell: help, ls, cat, mem, tasks, reboot, VGA/debug console, and exception proof ok'
