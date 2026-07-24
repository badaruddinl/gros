#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-stage2.gwo"}

fail() { echo "error: $1" >&2; exit 1; }

[ -f "$FILE" ] || fail "file not found: $FILE"
[ "$(wc -c < "$FILE" | tr -d ' ')" = "2560" ] || fail "headered stage-2 image must be 2560 bytes"

HEADER=$(dd if="$FILE" bs=1 skip=512 count=32 2> /dev/null | od -An -tx1 -v | tr -d ' \n')
[ "${HEADER:0:8}" = "47524f00" ] || fail "missing accepted headered stage-2 seed header"
[ "${HEADER:8:4}" = "2000" ] || fail "missing accepted headered stage-2 seed header"
[ "${HEADER:12:4}" = "0000" ] || fail "missing accepted headered stage-2 seed header"
[ "${HEADER:16:8}" = "00000000" ] || fail "missing accepted headered stage-2 seed header"
[ "${HEADER:24:4}" = "0000" ] || fail "missing accepted headered stage-2 seed header"
[ "${HEADER:28:4}" = "0000" ] || fail "missing accepted headered stage-2 seed header"
[ "${HEADER:32:8}" = "e0070000" ] || fail "missing accepted headered stage-2 seed header"
[ "${HEADER:40:8}" = "00000000" ] || fail "missing accepted headered stage-2 seed header"
[ "${HEADER:48:16}" = "0000000000000000" ] || fail "missing accepted headered stage-2 seed header"

PAYLOAD=$(dd if="$FILE" bs=1 skip=544 count=2016 2> /dev/null | od -An -tx1 -v | tr -d ' \n')
case "$PAYLOAD" in
    *"47724f532076302e35"*) ;;
    *) fail "headered stage-2 payload must contain runtime banner" ;;
esac

if command -v ndisasm > /dev/null 2>&1; then
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    dd if="$FILE" bs=512 count=1 2> /dev/null > "$TMP_DIR/stage1.gwo"
    ndisasm -b 16 -o 0x7c00 "$TMP_DIR/stage1.gwo" > "$TMP_DIR/stage1.ndisasm"
    grep -E '[[:space:]]cmp[[:space:]]+word[[:space:]]+\[0x8000\],0x5247' "$TMP_DIR/stage1.ndisasm" > /dev/null ||
        fail "stage-1 must validate header magic"
    grep -E '[[:space:]]add[[:space:]]+bx,0x8020' "$TMP_DIR/stage1.ndisasm" > /dev/null ||
        fail "stage-1 must add header size to entry offset"
    grep -E '[[:space:]]retf' "$TMP_DIR/stage1.ndisasm" > /dev/null ||
        fail "stage-1 must transfer through validated dynamic entry"
fi

echo "file              : $FILE"
echo "headered stage-2  : ok"
