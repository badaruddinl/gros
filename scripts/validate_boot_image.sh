#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REQUIRE_NDISASM=0

usage() {
    echo "usage: validate_boot_image.sh [--require-ndisasm] [image.gro]" >&2
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
            break
            ;;
    esac
done

if [ "$#" -gt 1 ]; then
    usage
    exit 2
fi

FILE=${1:-"$ROOT/build/gros-v0.5.gro"}

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

[ -f "$FILE" ] || fail "file not found: $FILE"

SIZE=$(wc -c < "$FILE" | tr -d ' ')
SIG=$(tail -c 2 "$FILE" | od -An -tx1 | tr -d ' \n')

echo "file     : $FILE"
echo "size     : $SIZE bytes"
echo "signature: $SIG"

[ "$SIZE" = "512" ] || fail "boot sector must be exactly 512 bytes"
[ "$((SIZE % 512))" -eq 0 ] || fail "image size must be a multiple of 512 bytes"
[ "$SIG" = "55aa" ] || fail "boot signature must be 55aa"

if command -v ndisasm > /dev/null 2>&1; then
    DISASM=$(mktemp)
    trap 'rm -f "$DISASM"' EXIT

    ndisasm -b 16 -o 0x7c00 "$FILE" > "$DISASM"
    require_instruction "$DISASM" '[[:space:]]int[[:space:]]+0x10' 'BIOS video interrupt'
    require_instruction "$DISASM" '[[:space:]]int[[:space:]]+0x16' 'BIOS keyboard interrupt'
    require_instruction "$DISASM" '[[:space:]]int[[:space:]]+0x19' 'BIOS bootstrap interrupt'
    echo "ndisasm  : ok"
elif [ "$REQUIRE_NDISASM" -eq 1 ]; then
    fail "ndisasm is required for this validation"
else
    echo "ndisasm  : skipped"
fi

echo "ok: validated boot image"
