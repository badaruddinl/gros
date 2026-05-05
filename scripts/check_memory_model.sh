#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEFAULT_FILE="$ROOT/build/gros-stage2.gro"
SPEC_FILE="$ROOT/docs/14-real16-memory-model.md"
FILE="$DEFAULT_FILE"

PROFILE="gros.x86.bios.real16.stage2.v0"
IMAGE_SIZE=2560
SECTOR_SIZE=512
STAGE1_SIZE=512
STAGE2_SIZE=2048

IVT_START=$((0x0000))
IVT_END=$((0x03ff))
BDA_START=$((0x0400))
BDA_END=$((0x04ff))
SCRATCH_START=$((0x0500))
SCRATCH_END=$((0x6fff))
STACK_START=$((0x7000))
STACK_END=$((0x7bff))
STAGE1_START=$((0x7c00))
STAGE1_END=$((0x7dff))
GUARD_START=$((0x7e00))
GUARD_END=$((0x7fff))
STAGE2_START=$((0x8000))
STAGE2_END=$((0x87ff))
EXPANSION_START=$((0x8800))
EXPANSION_END=$((0x9fff))
PLATFORM_START=$((0xa000))
PLATFORM_END=$((0xffff))

usage() {
    echo "usage: check_memory_model.sh [image.gro]" >&2
}

fail() {
    echo "error: $1" >&2
    exit 1
}

hex4() {
    printf '%04Xh' "$1"
}

hex5() {
    printf '%05Xh' "$1"
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
        *) fail "missing memory model byte fixture: $name" ;;
    esac
}

require_range() {
    local start=$1
    local end=$2
    local name=$3

    [ "$start" -le "$end" ] || fail "$name has invalid range"
    [ "$start" -ge "$IVT_START" ] || fail "$name starts before real16 low memory"
    [ "$end" -le "$PLATFORM_END" ] || fail "$name exceeds first 64 KiB"
}

require_adjacent() {
    local left_end=$1
    local right_start=$2
    local name=$3

    [ "$((left_end + 1))" -eq "$right_start" ] || fail "$name must be adjacent"
}

require_ordered() {
    local left_end=$1
    local right_start=$2
    local name=$3

    [ "$left_end" -lt "$right_start" ] || fail "$name ranges overlap"
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
SIG=$(dd if="$FILE" bs=1 skip=510 count=2 2> /dev/null | od -An -tx1 | tr -d ' \n')
STAGE1_HEX=$(hex_of_region "$FILE" 0 "$STAGE1_SIZE")
STAGE2_HEX=$(hex_of_region "$FILE" "$STAGE1_SIZE" "$STAGE2_SIZE")

echo "file       : $FILE"
echo "profile    : $PROFILE"
echo "image size : $SIZE bytes"

[ "$SIZE" = "$IMAGE_SIZE" ] || fail "stage-2 image must be $IMAGE_SIZE bytes"
[ "$((SIZE % SECTOR_SIZE))" -eq 0 ] || fail "image size must be sector aligned"
[ "$SIG" = "55aa" ] || fail "stage-1 boot signature must be 55aa"
[ -n "$STAGE2_HEX" ] || fail "stage-2 payload must not be empty"

require_range "$IVT_START" "$IVT_END" "IVT"
require_range "$BDA_START" "$BDA_END" "BDA"
require_range "$SCRATCH_START" "$SCRATCH_END" "scratch"
require_range "$STACK_START" "$STACK_END" "stack"
require_range "$STAGE1_START" "$STAGE1_END" "stage-1"
require_range "$GUARD_START" "$GUARD_END" "guard"
require_range "$STAGE2_START" "$STAGE2_END" "stage-2"
require_range "$EXPANSION_START" "$EXPANSION_END" "stage-2 expansion"
require_range "$PLATFORM_START" "$PLATFORM_END" "platform"

require_adjacent "$IVT_END" "$BDA_START" "IVT and BDA"
require_adjacent "$BDA_END" "$SCRATCH_START" "BDA and scratch"
require_adjacent "$SCRATCH_END" "$STACK_START" "scratch and stack"
require_adjacent "$STACK_END" "$STAGE1_START" "stack and stage-1"
require_adjacent "$STAGE1_END" "$GUARD_START" "stage-1 and guard"
require_adjacent "$GUARD_END" "$STAGE2_START" "guard and stage-2"
require_adjacent "$STAGE2_END" "$EXPANSION_START" "stage-2 and expansion"
require_ordered "$EXPANSION_END" "$PLATFORM_START" "expansion and platform"

[ "$((STAGE1_END - STAGE1_START + 1))" -eq "$STAGE1_SIZE" ] || fail "stage-1 range must be 512 bytes"
[ "$((STAGE2_END - STAGE2_START + 1))" -eq "$STAGE2_SIZE" ] || fail "stage-2 range must be 2048 bytes"
[ "$((STACK_END + 1))" -eq "$STAGE1_START" ] || fail "stack seed must stay below 7C00h"

require_hex "$STAGE1_HEX" "fa31c08ed88ec08ed0bc007cfbfc" "stage-1 real16 segment and stack setup"
require_hex "$STAGE1_HEX" "b80402bb0080b90200" "stage-1 reads 4 sectors to 0000:8000 from sector 2"
require_hex "$STAGE1_HEX" "ea00800000" "stage-1 jumps to 0000:8000"
require_hex "$STAGE2_HEX" "fa31c08ed88ec08ed0bc007c" "stage-2 real16 segment and stack setup"
require_hex "$STAGE2_HEX" "c706c000" "stage-2 installs int 30h offset in IVT"
require_hex "$STAGE2_HEX" "c706c2000000" "stage-2 installs int 30h segment 0000 in IVT"
require_hex "$STAGE2_HEX" "b80001cd30c3" "runtime string service uses DS:SI near pointer"

require_doc_text "$PROFILE" "profile name"
require_doc_text "0000:8000" "stage-2 load address"
require_doc_text "2048 bytes" "stage-2 payload size"
require_doc_text "07000h..07BFFh" "stack range"
require_doc_text "08000h..087FFh" "stage-2 range"
require_doc_text "There is no heap in this seed." "no-heap rule"

echo "ivt        : $(hex5 "$IVT_START")..$(hex5 "$IVT_END")"
echo "bda        : $(hex5 "$BDA_START")..$(hex5 "$BDA_END")"
echo "stack      : $(hex5 "$STACK_START")..$(hex5 "$STACK_END")"
echo "stage-1    : $(hex5 "$STAGE1_START")..$(hex5 "$STAGE1_END")"
echo "guard      : $(hex5 "$GUARD_START")..$(hex5 "$GUARD_END")"
echo "stage-2    : $(hex5 "$STAGE2_START")..$(hex5 "$STAGE2_END")"
echo "near ptr   : DS:$(hex4 "$STAGE2_START") seed"
echo "heap       : none"
echo "memory ABI : ok"
