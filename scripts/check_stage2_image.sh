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

require_text() {
    local file=$1
    local text=$2
    local name=$3
    grep -aF "$text" "$file" > /dev/null || fail "missing expected text: $name"
}

require_near_boot_drive_reload() {
    local disasm=$1
    local jump_line reload_line

    jump_line=$(grep -nE '[[:space:]]jmp[[:space:]]+0x0:0x8000' "$disasm" | head -n 1 | cut -d: -f1)
    [ -n "$jump_line" ] || fail "missing expected instruction: stage-2 far jump"

    reload_line=$(awk -v jump="$jump_line" '
        NR < jump && /[[:space:]]mov[[:space:]]+dl,\[0x[0-9a-fA-F]+\]/ { line = NR }
        END { if (line) print line }
    ' "$disasm")

    [ -n "$reload_line" ] || fail "missing expected instruction: boot drive reload before stage-2 jump"
    [ "$((jump_line - reload_line))" -le 2 ] || fail "boot drive reload must be adjacent to stage-2 jump"
}

require_stage2_runtime_gate() {
    local disasm=$1
    local vector_line segment_line first_int30_line handler_offset handler_value

    vector_line=$(grep -nE '[[:space:]]mov[[:space:]]+word[[:space:]]+\[0xc0\],0x8[0-7][0-9a-fA-F]{2}' "$disasm" | head -n 1 | cut -d: -f1)
    segment_line=$(grep -nE '[[:space:]]mov[[:space:]]+word[[:space:]]+\[0xc2\],0x0' "$disasm" | head -n 1 | cut -d: -f1)
    first_int30_line=$(grep -nE '[[:space:]]int[[:space:]]+0x30' "$disasm" | head -n 1 | cut -d: -f1)

    [ -n "$vector_line" ] || fail "missing expected instruction: int 30h IVT offset install"
    [ -n "$segment_line" ] || fail "missing expected instruction: int 30h IVT segment install"
    [ -n "$first_int30_line" ] || fail "missing expected instruction: runtime service probe int 30h"
    [ "$vector_line" -lt "$first_int30_line" ] || fail "int 30h vector must be installed before first runtime call"
    [ "$segment_line" -lt "$first_int30_line" ] || fail "int 30h segment must be installed before first runtime call"

    handler_offset=$(awk '/[[:space:]]mov[[:space:]]+word[[:space:]]+\[0xc0\],0x[0-9a-fA-F]+/ {
        sub(/.*0x/, "")
        print
        exit
    }' "$disasm")
    handler_value=$((16#$handler_offset))
    [ "$handler_value" -ge $((0x8000)) ] || fail "int 30h handler must be inside stage-2 payload"
    [ "$handler_value" -le $((0x87ff)) ] || fail "int 30h handler must be inside stage-2 payload"

    require_instruction "$disasm" '[[:space:]]or[[:space:]]+ax,ax' 'runtime/control probe selector check'
    require_instruction "$disasm" '[[:space:]]mov[[:space:]]+ax,0x1' 'unsupported runtime service error code'
    require_instruction "$disasm" '[[:space:]]or[[:space:]]+word[[:space:]]+\[bp\+0x6\],byte[[:space:]]+\+0x1' 'unsupported runtime service CF=1 return'
    require_instruction "$disasm" '[[:space:]]and[[:space:]]+word[[:space:]]+\[bp\+0x6\],byte[[:space:]]+-0x2' 'runtime/control probe CF=0 return'
    require_instruction "$disasm" '[[:space:]]iret' 'runtime service interrupt return'
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
    STAGE2="$TMP_DIR/stage2.gro"
    STAGE1_DISASM="$TMP_DIR/stage1.ndisasm"
    STAGE2_DISASM="$TMP_DIR/stage2.ndisasm"

    dd if="$FILE" of="$STAGE1" bs=512 count=1 2> /dev/null
    dd if="$FILE" of="$STAGE2" bs=512 skip=1 count=4 2> /dev/null
    ndisasm -b 16 -o 0x7c00 "$STAGE1" > "$STAGE1_DISASM"
    ndisasm -b 16 -o 0x8000 "$STAGE2" > "$STAGE2_DISASM"

    require_instruction "$STAGE1_DISASM" '[[:space:]]mov[[:space:]]+ax,0x204' 'stage-2 sector read count'
    require_instruction "$STAGE1_DISASM" '[[:space:]]mov[[:space:]]+bx,0x8000' 'stage-2 load offset'
    require_instruction "$STAGE1_DISASM" '[[:space:]]mov[[:space:]]+cx,0x2' 'stage-2 starting sector'
    require_instruction "$STAGE1_DISASM" '[[:space:]]int[[:space:]]+0x13' 'BIOS disk read interrupt'
    require_instruction "$STAGE1_DISASM" '[[:space:]]jmp[[:space:]]+0x0:0x8000' 'stage-2 far jump'
    require_near_boot_drive_reload "$STAGE1_DISASM"

    require_text "$STAGE2" 'GrOS v0.5' 'stage-2 banner'
    require_text "$STAGE2" 'gr> ' 'stage-2 prompt'
    require_instruction "$STAGE2_DISASM" '[[:space:]]int[[:space:]]+0x16' 'keyboard read interrupt'
    require_instruction "$STAGE2_DISASM" '[[:space:]]int[[:space:]]+0x10' 'video interrupt'
    require_instruction "$STAGE2_DISASM" '[[:space:]]int[[:space:]]+0x19' 'BIOS reboot interrupt'
    require_stage2_runtime_gate "$STAGE2_DISASM"
    echo "ndisasm  : ok"
elif [ "$REQUIRE_NDISASM" -eq 1 ]; then
    fail "ndisasm is required for this validation"
else
    echo "ndisasm  : skipped"
fi

echo "ok: valid stage-2 boot image"
