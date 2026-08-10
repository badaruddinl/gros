#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-longmode.img"}

fail() {
    echo "error: $1" >&2
    exit 1
}

"$ROOT/scripts/check_grogan_x86_64_profile.sh" "$FILE" > /dev/null
HEX=$(od -An -tx1 -v "$FILE" | tr -d ' \n')

require_hex() {
    case "$HEX" in
        *"$1"*)
            ;;
        *)
            fail "$2"
            ;;
    esac
}

require_hex b011e620e6a0 "missing master/slave PIC initialization"
require_hex b036e643 "missing PIT command initialization"
require_hex b0ffe640b0ffe640 "missing PIT divisor initialization"
require_hex e460 "missing keyboard data read"
require_hex fb "missing interrupt enable"
require_hex cf "missing iretq IRQ return"
require_hex_count_at_least() {
    local count
    count=$(printf '%s' "$HEX" | grep -o "$1" | wc -l | tr -d ' ')
    [ "$count" -ge "$2" ] || fail "$3"
}

require_hex_count_at_least 50 3 "missing IRQ/exception register preservation"

echo "Grogan interrupts: PIC, PIT, keyboard IRQ, timer IRQ, frame preservation, and iretq ok"
