#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEFAULT_FILE="$ROOT/build/gros-stage2.gwo"
SPEC_FILE="$ROOT/docs/14-real16-memory-model.md"
FILE="$DEFAULT_FILE"

STAGE1_SIZE=512
STAGE2_SIZE=2048
STAGE2_START=$((0x8000))
STAGE2_END=$((0x87ff))

usage() {
    echo "usage: check_near_pointers.sh [image.gwo]" >&2
}

fail() {
    echo "error: $1" >&2
    exit 1
}

hex4() {
    printf '%04Xh' "$1"
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

u16le_to_dec() {
    local le=$1
    local lo=${le:0:2}
    local hi=${le:2:2}
    echo $((16#$hi$lo))
}

require_doc_text() {
    local text=$1
    local name=$2
    grep -F "$text" "$SPEC_FILE" > /dev/null || fail "memory model spec missing $name"
}

require_hex() {
    local haystack=$1
    local needle=$2
    local name=$3
    case "$haystack" in
        *"$needle"*) ;;
        *) fail "missing near-pointer byte fixture: $name" ;;
    esac
}

require_pointer_in_stage2() {
    local pointer=$1
    local name=$2

    [ "$pointer" -ge "$STAGE2_START" ] || fail "$name points before stage-2: $(hex4 "$pointer")"
    [ "$pointer" -le "$STAGE2_END" ] || fail "$name points past stage-2: $(hex4 "$pointer")"
}

check_si_write_pointers() {
    local matches count match imm pointer

    matches=$(printf '%s\n' "$STAGE2_HEX" | grep -Eo 'be[0-9a-f]{4}e8[0-9a-f]{4}' || true)
    count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')
    [ "$count" -ge 6 ] || fail "expected at least 6 SI write pointer loads, got $count"

    while IFS= read -r match; do
        [ -n "$match" ] || continue
        imm=${match:2:4}
        pointer=$(u16le_to_dec "$imm")
        require_pointer_in_stage2 "$pointer" "SI write immediate"
    done <<EOF
$matches
EOF
}

check_compare_pointers() {
    local matches count match si_imm di_imm si_pointer di_pointer

    matches=$(printf '%s\n' "$STAGE2_HEX" | grep -Eo 'be[0-9a-f]{4}bf[0-9a-f]{4}e8[0-9a-f]{4}' || true)
    count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')
    [ "$count" -ge 4 ] || fail "expected 4 SI/DI compare pointer pairs, got $count"

    while IFS= read -r match; do
        [ -n "$match" ] || continue
        si_imm=${match:2:4}
        di_imm=${match:8:4}
        si_pointer=$(u16le_to_dec "$si_imm")
        di_pointer=$(u16le_to_dec "$di_imm")
        require_pointer_in_stage2 "$si_pointer" "SI compare immediate"
        require_pointer_in_stage2 "$di_pointer" "DI compare immediate"
    done <<EOF
$matches
EOF
}

check_input_buffer_pointer() {
    local matches count match imm pointer

    matches=$(printf '%s\n' "$STAGE2_HEX" | grep -Eo 'bf[0-9a-f]{4}31c9' || true)
    count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')
    [ "$count" -eq 1 ] || fail "expected one DI input buffer pointer load, got $count"

    match=$matches
    imm=${match:2:4}
    pointer=$(u16le_to_dec "$imm")
    require_pointer_in_stage2 "$pointer" "DI input buffer immediate"
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
[ -f "$SPEC_FILE" ] || fail "spec file not found: $SPEC_FILE"

SIZE=$(size_of "$FILE")
[ "$SIZE" = "2560" ] || fail "stage-2 boot image must be 2560 bytes"

STAGE2_HEX=$(hex_of_region "$FILE" "$STAGE1_SIZE" "$STAGE2_SIZE")
[ -n "$STAGE2_HEX" ] || fail "stage-2 payload must not be empty"

INT30_VECTOR=$(printf '%s\n' "$STAGE2_HEX" | grep -Eo 'c706c000[0-9a-f]{4}c706c2000000' | head -n 1 || true)
[ -n "$INT30_VECTOR" ] || fail "missing int 30h vector install fixture"
HANDLER_IMM=${INT30_VECTOR:8:4}
HANDLER_PTR=$(u16le_to_dec "$HANDLER_IMM")
require_pointer_in_stage2 "$HANDLER_PTR" "int 30h handler"

check_si_write_pointers
check_compare_pointers
check_input_buffer_pointer

require_hex "$STAGE2_HEX" "b80001cd30c3" "write_string forwards DS:SI to console/text.write_cstr"
require_hex "$STAGE2_HEX" "56fce8" "console/text.write_cstr preserves SI before local string walk"
require_doc_text "u16 offset within segment 0000" "near pointer representation"
require_doc_text "DS:offset" "default data pointer rule"
require_doc_text 'Pointer-sized `.grw` types remain reserved' 'reserved `.grw` pointer rule'

echo "file       : $FILE"
echo "stage-2    : $(hex4 "$STAGE2_START")..$(hex4 "$STAGE2_END")"
echo "int30      : $(hex4 "$HANDLER_PTR")"
echo "checked    : SI and DI near immediates"
echo "near ptrs  : ok"
