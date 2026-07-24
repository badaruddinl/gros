#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-stage2.gwo"}
fail() { echo "error: $1" >&2; exit 1; }
[ -f "$FILE" ] || fail "file not found: $FILE"
command -v qemu-system-i386 > /dev/null 2>&1 || fail "qemu-system-i386 is required"
TRACE=$(mktemp)
trap 'rm -f "$TRACE"' EXIT
set +e
timeout 3 qemu-system-i386 -drive format=raw,file="$FILE" -display none -no-reboot -no-shutdown -d in_asm -D "$TRACE" > /dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" = 124 ] || fail "qemu must stay running, got status $STATUS"
grep -E '0x00008020|0x8020' "$TRACE" > /dev/null || fail "qemu did not execute grogan_entry 0000:8020"
echo "grogan seed: qemu executed grogan_entry"
