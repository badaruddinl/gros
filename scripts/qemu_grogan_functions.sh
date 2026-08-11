#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/functions.img"
LOG="$TMP_DIR/debug.log"
MONITOR_LOG="$TMP_DIR/monitor.log"

GROGAN_USER_SOURCE="$ROOT/examples/grown-alpha/functions.grw" \
    "$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
set +e
{
    sleep 1
    printf 'sendkey e\n'
    sleep 0.5
    printf 'quit\n'
} | timeout 15 qemu-system-x86_64 \
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
[ "$STATUS" = 0 ] || { cat "$MONITOR_LOG" >&2; exit 1; }
grep -aF '28' "$LOG" > /dev/null || { cat "$LOG" >&2; exit 1; }
echo 'Grogan functions: ring-3 call/return parity and process isolation ok'
