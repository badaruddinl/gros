#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEFAULT_FILE="$ROOT/build/gros-stage2.gwo"
FILE="$DEFAULT_FILE"

STAGE1_SIZE=512
STAGE2_SIZE=2048
IMAGE_SIZE=2560
STAGE2_ORIGIN=$((0x8000))

usage() {
    echo "usage: check_stage2_input.sh [image.gwo]" >&2
}

fail() {
    echo "error: $1" >&2
    exit 1
}

hex_of_region() {
    local file=$1
    local skip=$2
    local count=$3

    dd if="$file" bs=1 skip="$skip" count="$count" 2> /dev/null |
        od -An -tx1 -v |
        tr -d ' \n'
}

hex_pattern_offset() {
    local needle=$1
    local occurrence=${2:-1}
    local rest=$STAGE2_HEX
    local offset=0
    local index=0
    local prefix

    while :; do
        case "$rest" in
            *"$needle"*)
                prefix=${rest%%"$needle"*}
                offset=$((offset + ${#prefix} / 2))
                index=$((index + 1))
                if [ "$index" -eq "$occurrence" ]; then
                    printf '%s' "$offset"
                    return
                fi
                rest=${rest#*"$needle"}
                offset=$((offset + ${#needle} / 2))
                ;;
            *)
                fail "missing stage-2 input data fixture: $needle"
                ;;
        esac
    done
}

addr_le_for_offset() {
    local offset=$1
    local address=$((STAGE2_ORIGIN + offset))

    printf '%02x%02x' "$((address & 0xff))" "$(((address >> 8) & 0xff))"
}

addr_le_for_pattern() {
    local needle=$1
    local occurrence=${2:-1}
    local offset

    offset=$(hex_pattern_offset "$needle" "$occurrence")
    addr_le_for_offset "$offset"
}

require_hex_regex() {
    local pattern=$1
    local name=$2

    printf '%s\n' "$STAGE2_HEX" | grep -Eq "$pattern" ||
        fail "missing stage-2 input loop fixture: $name"
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

SIZE=$(wc -c < "$FILE" | tr -d ' ')
[ "$SIZE" = "$IMAGE_SIZE" ] || fail "stage-2 image must be $IMAGE_SIZE bytes"

STAGE2_HEX=$(hex_of_region "$FILE" "$STAGE1_SIZE" "$STAGE2_SIZE")
STAGE2_NONZERO=$(dd if="$FILE" bs=1 skip="$STAGE1_SIZE" count="$STAGE2_SIZE" 2> /dev/null | od -An -tx1 -v | tr -d ' 0\n')

[ -n "$STAGE2_HEX" ] || fail "stage-2 payload must not be empty"
[ -n "$STAGE2_NONZERO" ] || fail "stage-2 payload must not be empty"

PROMPT_TEXT=$(addr_le_for_pattern "67726f756e643e2000")
NEWLINE_TEXT=$(addr_le_for_pattern "0d0a00" 2)
BACKSPACE_TEXT=$(addr_le_for_pattern "08200800")
UNKNOWN_OFFSET=$(hex_pattern_offset "3f0d0a00")
INPUT_BUFFER=$(addr_le_for_offset "$((UNKNOWN_OFFSET + 4))")

require_hex_regex "be${PROMPT_TEXT}e8[0-9a-f]{4}bf${INPUT_BUFFER}31c9" "prompt and input buffer reset"
require_hex_regex "31c0cd16" "keyboard read"
require_hex_regex "3c0d74[0-9a-f]{2}" "enter branch"
require_hex_regex "3c0874[0-9a-f]{2}" "backspace branch"
require_hex_regex "3c2072[0-9a-f]{2}" "control character reject"
require_hex_regex "83f90f73[0-9a-f]{2}" "max input length guard"
require_hex_regex "88c3aa41b80101cd30" "store and runtime echo"
require_hex_regex "83f90074[0-9a-f]{2}4f49be${BACKSPACE_TEXT}e8[0-9a-f]{4}eb[0-9a-f]{2}" "backspace edit path"
require_hex_regex "b000aabe${NEWLINE_TEXT}e8[0-9a-f]{4}83f90074[0-9a-f]{2}" "enter terminates line and handles empty input"

echo "file              : $FILE"
echo "stage-2           : $STAGE2_SIZE bytes"
echo "input loop        : ok"
