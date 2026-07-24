#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-longmode.img"}
command -v qemu-system-x86_64 > /dev/null 2>&1 || { echo 'error: qemu-system-x86_64 is required' >&2; exit 1; }
[ -f "$FILE" ] || { echo "error: file not found: $FILE" >&2; exit 1; }
LOG=$(mktemp); trap 'rm -f "$LOG"' EXIT
set +e
timeout 4 qemu-system-x86_64 -drive format=raw,file="$FILE" -display none -no-reboot -no-shutdown -debugcon file:"$LOG" -global isa-debugcon.iobase=0xe9 > /dev/null 2>&1
STATUS=$?
set -e
[ "$STATUS" = 124 ] || { echo "error: qemu status $STATUS" >&2; exit 1; }
grep -F 'LM64' "$LOG" > /dev/null || { echo 'error: long-mode marker missing' >&2; exit 1; }
echo 'long mode: qemu reached x86_64 entry'
