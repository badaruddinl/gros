#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/generated/minimal-main-void.gwo"}

fail() { echo "error: $1" >&2; exit 1; }
[ -f "$FILE" ] || fail "file not found: $FILE"
command -v qemu-system-i386 > /dev/null 2>&1 || fail "qemu-system-i386 is required"

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
set +e
timeout 3 qemu-system-i386 -drive format=raw,file="$FILE" -display none -no-reboot -no-shutdown -d in_asm -D "$LOG" > /dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" = 124 ] || fail "qemu must remain halted, got status $STATUS"
grep -E '0x00008020|0x8020' "$LOG" > /dev/null || fail "qemu trace did not execute compiled payload entry 0000:8020"
echo "generated minimal main: qemu executed 0000:8020"
