#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEFAULT_FILE="$ROOT/build/gros-stage2.gwo"
FILE="$DEFAULT_FILE"

usage() {
    echo "usage: check_stage2_debugcon.sh [image.gwo]" >&2
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

if [ ! -f "$FILE" ] && [ "$FILE" = "$DEFAULT_FILE" ]; then
    "$ROOT/scripts/build_stage2_image.sh"
fi

[ -f "$FILE" ] || fail "file not found: $FILE"

SIZE=$(wc -c < "$FILE" | tr -d ' ')
[ "$SIZE" = "2560" ] || fail "stage-2 boot image must be 2560 bytes"

STAGE2_HEX=$(dd if="$FILE" bs=512 skip=1 count=4 2> /dev/null | od -An -tx1 -v | tr -d ' \n')
[ -n "$STAGE2_HEX" ] || fail "stage-2 payload must not be empty"

printf '%s\n' "$STAGE2_HEX" | grep -Eq 'ac84c074[0-9a-f]{2}e6e9b40ecd10' ||
    fail "missing stage-2 debug console mirror: string output path"
printf '%s\n' "$STAGE2_HEX" | grep -Eq '88d8e6e9b40ecd10' ||
    fail "missing stage-2 debug console mirror: character output path"

echo "file             : $FILE"
echo "debug console    : E9h mirror ok"
