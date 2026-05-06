#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEFAULT_FILE="$ROOT/build/gros-stage2.gwo"
FILE="$DEFAULT_FILE"

usage() {
    echo "usage: check_runtime_abi.sh [image.gwo]" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            usage
            exit 2
            ;;
        *)
            FILE=$1
            shift
            ;;
    esac
done

fail() {
    echo "error: $1" >&2
    exit 1
}

require_hex() {
    local hex=$1
    local name=$2
    case "$STAGE2_HEX" in
        *"$hex"*) ;;
        *) fail "missing runtime ABI byte fixture: $name" ;;
    esac
}

require_hex_regex() {
    local pattern=$1
    local name=$2
    printf '%s\n' "$STAGE2_HEX" | grep -Eq "$pattern" || fail "missing runtime ABI byte fixture: $name"
}

if [ ! -f "$FILE" ] && [ "$FILE" = "$DEFAULT_FILE" ]; then
    "$ROOT/scripts/build_stage2_image.sh"
fi

[ -f "$FILE" ] || fail "file not found: $FILE"

SIZE=$(wc -c < "$FILE" | tr -d ' ')
[ "$SIZE" = "2560" ] || fail "stage-2 boot image must be 2560 bytes"

STAGE2_HEX=$(dd if="$FILE" bs=512 skip=1 count=4 2> /dev/null | od -An -tx1 -v | tr -d ' \n')
[ -n "$STAGE2_HEX" ] || fail "stage-2 payload must not be empty"

require_hex "31c0cd30" "runtime/control probe call"
require_hex "67726f732e7838362e62696f732e7265616c31362e7374616765322e763000" "runtime/control profile_id text"
require_hex "b80001cd30c3" "console/text write selector call helper"
require_hex "88c3aa41b80101cd30" "console/text write-char echo call"
require_hex "b80201cd30" "console/text write-crlf selector call"
require_hex "5589e5" "runtime interrupt handler stack frame"
require_hex "09c074" "runtime/control probe selector branch"
require_hex "3d010074" "runtime/control version selector branch"
require_hex "3d020074" "runtime/control profile_id selector branch"
require_hex "3d000174" "console/text write selector branch"
require_hex "3d010174" "console/text write-char selector branch"
require_hex "3d020174" "console/text write-crlf selector branch"
require_hex "88d8b40ecd10" "console/text write-char service body"
require_hex_regex "b80100eb[0-9a-f]{2}" "runtime/control version returns AX=0001h and jumps to success"
require_hex_regex "be[0-9a-f]{4}eb[0-9a-f]{2}" "runtime/control profile_id returns DS:SI and jumps to success"
require_hex_regex "56be[0-9a-f]{4}fce8[0-9a-f]{4}5eeb[0-9a-f]{2}" "console/text write-crlf preserves SI and jumps to success"
require_hex "b80100834e06015dcf" "unsupported selector returns CF=1 AX=0001h"
require_hex "836606fe5dcf" "successful selector clears CF and preserves AX result"
require_hex "31c0836606fe5dcf" "successful selector returns CF=0 AX=0000h"
require_hex_regex "56fce8[0-9a-f]{4}5e31c0836606fe5dcf" "console/text preserves SI and falls through to success"

echo "file        : $FILE"
echo "runtime ABI : ok"
