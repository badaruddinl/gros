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

DEBUG_LOG_FIRST=$(mktemp)
MONITOR_LOG_FIRST=$(mktemp)
DEBUG_LOG_SECOND=$(mktemp)
MONITOR_LOG_SECOND=$(mktemp)
cleanup() {
    if [ "${GROGAN_QEMU_KEEP_LOG:-0}" = 1 ]; then
        echo "first debug log: $DEBUG_LOG_FIRST" >&2
        echo "first monitor log: $MONITOR_LOG_FIRST" >&2
        echo "second debug log: $DEBUG_LOG_SECOND" >&2
        echo "second monitor log: $MONITOR_LOG_SECOND" >&2
        return
    fi
    rm -f "$DEBUG_LOG_FIRST" "$MONITOR_LOG_FIRST" "$DEBUG_LOG_SECOND" "$MONITOR_LOG_SECOND"
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

run_qemu() {
    local debug_log=$1 monitor_log=$2
    shift 2
{
    sleep 1
    for word in "$@"; do send_word "$word"; done
    sleep 0.5
    printf 'quit\n'
} | timeout 15 qemu-system-x86_64 \
    -drive format=raw,file="$FILE" \
    -display none \
    -monitor stdio \
    -no-reboot \
    -no-shutdown \
    -debugcon "file:$debug_log" \
    -global isa-debugcon.iobase=0xe9 \
    > "$monitor_log" 2>&1
}

set +e
run_qemu "$DEBUG_LOG_FIRST" "$MONITOR_LOG_FIRST" save ls cat
STATUS_FIRST=$?
run_qemu "$DEBUG_LOG_SECOND" "$MONITOR_LOG_SECOND" ls cat mem tasks reboot
STATUS_SECOND=$?
set -e
[ "$STATUS_FIRST" = 0 ] || { cat "$MONITOR_LOG_FIRST" >&2; fail "first qemu status $STATUS_FIRST"; }
[ "$STATUS_SECOND" = 0 ] || { cat "$MONITOR_LOG_SECOND" >&2; fail "second qemu status $STATUS_SECOND"; }

require_text() {
    local text=$1
    local name=$2
    grep -aF "$text" "$DEBUG_LOG_SECOND" > /dev/null || fail "missing shell transcript: $name"
}

require_first_text() {
    local text=$1
    local name=$2
    grep -aF "$text" "$DEBUG_LOG_FIRST" > /dev/null || fail "missing first-boot transcript: $name"
}

require_text 'LM64IDTGRO64PGM2PMEMF1F2HEAPT1T2FSOK' 'bootstrap'
require_text 'SCFGGWO2OK' 'syscall/GWO2 user boundary'
require_text '28' 'GWO2 VM output'
require_text 'IRQ' 'timer IRQ'
require_text 'P1' 'preemptive task-one context'
require_text 'P2' 'preemptive task-two context'
require_first_text 'SAVE OK' 'persistent save response'
require_text 'hello.grw' 'persistent directory entry after reboot'
require_text 'target "gros.x86.bios.longmode.grogan.v1"' 'persistent source content after reboot'
require_text 'print_i32(28);' 'persistent source body after reboot'
require_text 'FRAMES HEAP PAGES' 'mem response'
require_text 'T1 T2' 'tasks response'
require_text 'REBOOT' 'reboot response'
require_text 'EX06' 'exception proof'

echo 'Grogan shell: GFS2 save/read persistence across reboot, diagnostics, scheduler, and exception proof ok'
