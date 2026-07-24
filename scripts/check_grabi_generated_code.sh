#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FIXTURE_DIR="$ROOT/fixtures/generated-code/abi-call-preserve"
FILE="${1:-$FIXTURE_DIR/expected.gwo}"
CONTRACT="$ROOT/docs/26-grabi-generated-code-compatibility.md"
EXPECTED_SIZE=2048

usage() {
    echo "usage: check_grabi_generated_code.sh [expected.gwo]" >&2
}

fail() {
    echo "error: $1" >&2
    exit 1
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

[ -f "$FILE" ] || fail "file not found: $FILE"
[ -f "$CONTRACT" ] || fail "contract file not found: $CONTRACT"
[ "$(wc -c < "$FILE" | tr -d ' ')" = "$EXPECTED_SIZE" ] ||
    fail "expected generated ABI fixture must be $EXPECTED_SIZE bytes"

HEX=$(od -An -tx1 -v "$FILE" | tr -d ' \n')

require_hex() {
    local needle=$1
    local name=$2

    case "$HEX" in
        *"$needle"*) ;;
        *) fail "missing generated ABI fixture: $name" ;;
    esac
}

require_hex "fcb81111bb2222b93333ba4444687777e8070083c402faf4ebfc" \
    "DF-clear entry, register arguments, stack argument, caller cleanup, and halt"
require_hex "5589e51e065657beaaaabfbbbb31c08ed88ec08b4604fc071f5f5e5dc3" \
    "callee frame, saved segments/registers, AX stack return, DF clear, and restore sequence"

case "$HEX" in
    *cd30*) fail "generated ABI fixture must not depend on GrSCall" ;;
esac

grep -F "grabi.real16.call.v1" "$CONTRACT" > /dev/null ||
    fail "generated ABI contract missing compatibility identity"
grep -F 'Arguments 0 through 3 are passed in `AX`, `BX`, `CX`, and `DX`.' "$CONTRACT" > /dev/null ||
    fail "generated ABI contract missing register argument rule"
grep -F "Additional arguments are pushed as 16-bit words from right to left." "$CONTRACT" > /dev/null ||
    fail "generated ABI contract missing stack argument rule"
grep -F "The caller removes stack arguments after a direct near call." "$CONTRACT" > /dev/null ||
    fail "generated ABI contract missing caller cleanup rule"
grep -F '`SI`, `DI`, `BP`, `DS`, and `ES` are callee-saved.' "$CONTRACT" > /dev/null ||
    fail "generated ABI contract missing callee preservation rule"

echo "file        : $FILE"
echo "grabi call  : grabi.real16.call.v1 ok"
