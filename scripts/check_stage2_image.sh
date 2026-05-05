#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEFAULT_FILE="$ROOT/build/gros-stage2.gro"
FILE="$DEFAULT_FILE"
REQUIRE_NDISASM=0

usage() {
    echo "usage: check_stage2_image.sh [--require-ndisasm] [image.gro]" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --require-ndisasm)
            REQUIRE_NDISASM=1
            shift
            ;;
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

require_instruction() {
    local disasm=$1
    local pattern=$2
    local name=$3
    grep -E "$pattern" "$disasm" > /dev/null || fail "missing expected instruction: $name"
}

if [ ! -f "$FILE" ] && [ "$FILE" = "$DEFAULT_FILE" ]; then
    "$ROOT/scripts/build_stage2_image.sh"
fi

[ -f "$FILE" ] || fail "file not found: $FILE"

SIZE=$(wc -c < "$FILE" | tr -d ' ')
SIG=$(dd if="$FILE" bs=1 skip=510 count=2 2> /dev/null | od -An -tx1 | tr -d ' \n')
STAGE2_NONZERO=$(dd if="$FILE" bs=1 skip=512 count=2048 2> /dev/null | od -An -tx1 | tr -d ' 0\n')

echo "file     : $FILE"
echo "size     : $SIZE bytes"
echo "signature: $SIG"

[ "$SIZE" = "2560" ] || fail "stage-2 boot image must be 2560 bytes"
[ "$((SIZE % 512))" -eq 0 ] || fail "stage-2 boot image size must be a multiple of 512 bytes"
[ "$SIG" = "55aa" ] || fail "stage-1 boot signature must be 55aa"
[ -n "$STAGE2_NONZERO" ] || fail "stage-2 payload must not be empty"

if command -v ndisasm > /dev/null 2>&1; then
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    STAGE1="$TMP_DIR/stage1.gro"
    DISASM="$TMP_DIR/stage1.ndisasm"

    dd if="$FILE" of="$STAGE1" bs=512 count=1 2> /dev/null
    ndisasm -b 16 -o 0x7c00 "$STAGE1" > "$DISASM"

    require_instruction "$DISASM" '[[:space:]]mov[[:space:]]+ax,0x204' 'stage-2 sector read count'
    require_instruction "$DISASM" '[[:space:]]mov[[:space:]]+bx,0x8000' 'stage-2 load offset'
    require_instruction "$DISASM" '[[:space:]]mov[[:space:]]+cx,0x2' 'stage-2 starting sector'
    require_instruction "$DISASM" '[[:space:]]int[[:space:]]+0x13' 'BIOS disk read interrupt'
    require_instruction "$DISASM" '[[:space:]]jmp[[:space:]]+0x0:0x8000' 'stage-2 far jump'
    echo "ndisasm  : ok"
elif [ "$REQUIRE_NDISASM" -eq 1 ]; then
    fail "ndisasm is required for this validation"
else
    echo "ndisasm  : skipped"
fi

echo "ok: valid stage-2 boot image"
