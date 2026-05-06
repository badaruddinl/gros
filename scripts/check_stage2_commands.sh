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
    echo "usage: check_stage2_commands.sh [image.gwo]" >&2
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
                fail "missing stage-2 command data fixture: $needle"
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
        fail "missing stage-2 command dispatch fixture: $name"
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
STAGE2_NONZERO=$(dd if="$FILE" bs=1 skip="$STAGE1_SIZE" count="$STAGE2_SIZE" 2> /dev/null | od -An -tx1 -v | tr -d ' 0\n')

[ -n "$STAGE2_HEX" ] || fail "stage-2 payload must not be empty"
[ -n "$STAGE2_NONZERO" ] || fail "stage-2 payload must not be empty"

CMD_HELP=$(addr_le_for_pattern "68656c7000")
CMD_VER=$(addr_le_for_pattern "76657200")
CMD_CLS=$(addr_le_for_pattern "636c7300")
CMD_REBOOT=$(addr_le_for_pattern "7265626f6f7400")
HELP_TEXT=$(addr_le_for_pattern "68656c702076657220636c73207265626f6f740d0a00")
VERSION_TEXT=$(addr_le_for_pattern "47724f532076302e350d0a00" 2)
UNKNOWN_TEXT=$(addr_le_for_pattern "3f0d0a00")
UNKNOWN_OFFSET=$(hex_pattern_offset "3f0d0a00")
INPUT_BUFFER=$(addr_le_for_offset "$((UNKNOWN_OFFSET + 4))")

require_hex_regex "be${INPUT_BUFFER}bf${CMD_HELP}e8[0-9a-f]{4}72[0-9a-f]{2}" "help command compare"
require_hex_regex "be${INPUT_BUFFER}bf${CMD_VER}e8[0-9a-f]{4}72[0-9a-f]{2}" "ver command compare"
require_hex_regex "be${INPUT_BUFFER}bf${CMD_CLS}e8[0-9a-f]{4}72[0-9a-f]{2}" "cls command compare"
require_hex_regex "be${INPUT_BUFFER}bf${CMD_REBOOT}e8[0-9a-f]{4}72[0-9a-f]{2}" "reboot command compare"
require_hex_regex "be${UNKNOWN_TEXT}e8[0-9a-f]{4}e9[0-9a-f]{4}" "unknown command fallback"
require_hex_regex "be${HELP_TEXT}e8[0-9a-f]{4}e9[0-9a-f]{4}" "help command action"
require_hex_regex "be${VERSION_TEXT}e8[0-9a-f]{4}e9[0-9a-f]{4}" "ver command action"
require_hex_regex "b80300cd10e9[0-9a-f]{4}" "cls command action"
require_hex_regex "cd19e9[0-9a-f]{4}" "reboot command action"
require_hex_regex "acae750684c075f8f9c3f8c3" "string_equal carry convention"

echo "file              : $FILE"
echo "stage-2           : $STAGE2_SIZE bytes"
echo "command dispatch  : ok"
