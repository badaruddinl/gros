#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-stage2.gwo"}

fail() { echo "error: $1" >&2; exit 1; }
[ -f "$FILE" ] || fail "file not found: $FILE"
command -v qemu-system-i386 > /dev/null 2>&1 || fail "qemu-system-i386 is required"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
MUTATED="$TMP_DIR/bad-header.gwo"
TRACE="$TMP_DIR/qemu.trace"
cp "$FILE" "$MUTATED"
printf '\000' | dd of="$MUTATED" bs=1 seek=512 count=1 conv=notrunc status=none

set +e
timeout 3 qemu-system-i386 -drive format=raw,file="$MUTATED" -display none -no-reboot -no-shutdown -d in_asm -D "$TRACE" > /dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" = 124 ] || fail "qemu must remain halted after header rejection, got status $STATUS"
grep -E '0x00007c00|0x7c00' "$TRACE" > /dev/null || fail "qemu trace did not execute stage-1"
if grep -E '0x00008020|0x8020' "$TRACE" > /dev/null; then
    fail "malformed header reached payload entry 0000:8020"
fi
echo "header rejection: qemu halted before 0000:8020"
