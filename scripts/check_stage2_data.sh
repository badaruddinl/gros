#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEFAULT_FILE="$ROOT/build/gros-stage2.gwo"
FILE="$DEFAULT_FILE"

STAGE1_SIZE=512
STAGE2_SIZE=2048
IMAGE_SIZE=2560

usage() {
    echo "usage: check_stage2_data.sh [image.gwo]" >&2
}

fail() {
    echo "error: $1" >&2
    exit 1
}

size_of() {
    wc -c < "$1" | tr -d ' '
}

hex_of_region() {
    local file=$1
    local skip=$2
    local count=$3
    dd if="$file" bs=1 skip="$skip" count="$count" 2> /dev/null | od -An -tx1 -v | tr -d ' \n'
}

count_hex() {
    local needle=$1
    local rest=$STAGE2_HEX
    local count=0

    while :; do
        case "$rest" in
            *"$needle"*)
                rest=${rest#*"$needle"}
                count=$((count + 1))
                ;;
            *)
                break
                ;;
        esac
    done

    echo "$count"
}

require_hex_count() {
    local needle=$1
    local minimum=$2
    local name=$3
    local count

    count=$(count_hex "$needle")
    [ "$count" -ge "$minimum" ] || fail "missing stage-2 data fixture: $name"
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

if [ ! -f "$FILE" ] && [ "$FILE" = "$DEFAULT_FILE" ]; then
    "$ROOT/scripts/build_stage2_image.sh"
fi

[ -f "$FILE" ] || fail "file not found: $FILE"

SIZE=$(size_of "$FILE")
[ "$SIZE" = "$IMAGE_SIZE" ] || fail "stage-2 image must be $IMAGE_SIZE bytes"

STAGE2_HEX=$(hex_of_region "$FILE" "$STAGE1_SIZE" "$STAGE2_SIZE")
TRAILING_ZERO_HEX=$(hex_of_region "$FILE" "$((STAGE1_SIZE + STAGE2_SIZE - 16))" 16)

[ -n "$STAGE2_HEX" ] || fail "stage-2 payload must not be empty"

require_hex_count "47724f532076302e350d0a00" 2 "banner and version text"
require_hex_count "67726f756e643e2000" 1 "prompt text"
require_hex_count "0d0a00" 2 "newline text"
require_hex_count "08200800" 1 "backspace text"
require_hex_count "68656c7000" 1 "help command"
require_hex_count "76657200" 1 "ver command"
require_hex_count "636c7300" 1 "cls command"
require_hex_count "7265626f6f7400" 1 "reboot command"
require_hex_count "68656c702076657220636c73207265626f6f740d0a00" 1 "help output"
require_hex_count "3f0d0a00" 1 "unknown command output"

[ "$TRAILING_ZERO_HEX" = "00000000000000000000000000000000" ] || fail "stage-2 command buffer tail must remain zero-filled"

echo "file       : $FILE"
echo "stage-2    : $STAGE2_SIZE bytes"
echo "strings    : ok"
echo "zero fill  : ok"
echo "data ABI   : ok"
