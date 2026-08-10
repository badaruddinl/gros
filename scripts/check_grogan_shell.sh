#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-longmode.img"}

fail() {
    echo "error: $1" >&2
    exit 1
}

"$ROOT/scripts/check_grogan_interrupts.sh" "$FILE" > /dev/null
HEX=$(od -An -tx1 -v "$FILE" | tr -d ' \n')

require_hex() {
    case "$HEX" in
        *"$1"*) ;;
        *) fail "$2" ;;
    esac
}

require_hex 68656c70206c7320636174206d656d207461736b73207265626f6f74 "missing shell help command set"
require_hex 488d47fc "missing filesystem payload ownership handoff"
require_hex 48890425 "missing filesystem payload pointer state"
require_hex 8a06 "missing fixed-length filesystem console read"
require_hex ffc9 "missing fixed-length filesystem read decrement"
require_hex 3a20 "missing filesystem name/payload separator"
require_hex 4652414d45532048454150205041474553 "missing memory response"
require_hex 5431205432 "missing task response"
require_hex ba00800b00 "missing VGA text console base"
require_hex 1c "missing enter key handling"
require_hex 0e "missing backspace key handling"
require_hex 68656c70 "missing help command"
require_hex 7265626f6f74 "missing reboot command"

case "$HEX" in
    *494e49543a2047524653*) fail "filesystem cat response is hardcoded instead of read" ;;
esac

echo "Grogan shell: command vocabulary, filesystem/memory/task responses, keyboard editing, and VGA console ok"
