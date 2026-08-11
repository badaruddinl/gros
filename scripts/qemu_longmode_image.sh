#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-longmode.img"}
command -v qemu-system-x86_64 > /dev/null 2>&1 || { echo 'error: qemu-system-x86_64 is required' >&2; exit 1; }
[ -f "$FILE" ] || { echo "error: file not found: $FILE" >&2; exit 1; }
LOG=$(mktemp)
MONITOR_LOG=$(mktemp)
cleanup() {
    rm -f "$LOG" "$MONITOR_LOG"
}
trap cleanup EXIT
set +e
{
    sleep 1
    for key in r e b o o t ret; do
        printf 'sendkey %s\n' "$key"
        sleep 0.12
    done
    sleep 0.5
    printf 'quit\n'
} | timeout 10 qemu-system-x86_64 \
    -drive format=raw,file="$FILE" \
    -display none \
    -monitor stdio \
    -no-reboot \
    -no-shutdown \
    -debugcon "file:$LOG" \
    -global isa-debugcon.iobase=0xe9 \
    > "$MONITOR_LOG" 2>&1
STATUS=$?
set -e
[ "$STATUS" = 0 ] || { cat "$MONITOR_LOG" >&2; echo "error: qemu status $STATUS" >&2; exit 1; }
grep -F 'LM64IDTGRO64PGM2PMEMF1F2HEAPT1T2FSOK' "$LOG" > /dev/null || { echo 'error: Grogan x86_64 bootstrap marker missing' >&2; exit 1; }
grep -F 'SCFGGWO1' "$LOG" > /dev/null || { echo 'error: syscall/GWO user-boundary proof missing' >&2; exit 1; }
grep -F 'SC1' "$LOG" > /dev/null || { echo 'error: console_write syscall proof missing' >&2; exit 1; }
grep -F 'SC2' "$LOG" > /dev/null || { echo 'error: process_exit syscall proof missing' >&2; exit 1; }
grep -F 'USEROK' "$LOG" > /dev/null || { echo 'error: user process completion proof missing' >&2; exit 1; }
grep -F 'IRQ' "$LOG" > /dev/null || { echo 'error: timer IRQ marker missing' >&2; exit 1; }
grep -F 'P1' "$LOG" > /dev/null || { echo 'error: preemptive task-one context missing' >&2; exit 1; }
grep -F 'P2' "$LOG" > /dev/null || { echo 'error: preemptive task-two context missing' >&2; exit 1; }
grep -F 'reboot' "$LOG" > /dev/null || { echo 'error: shell reboot command missing' >&2; exit 1; }
grep -F 'REBOOT' "$LOG" > /dev/null || { echo 'error: shell reboot response missing' >&2; exit 1; }
grep -F 'EX06' "$LOG" > /dev/null || { echo 'error: exception proof missing' >&2; exit 1; }
echo 'Grogan x86_64 profile: qemu initialized paging, IRQs, physical frames, heap, scheduler, boot filesystem, and exception handler'
