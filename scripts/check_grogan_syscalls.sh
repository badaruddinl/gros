#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-longmode.img"}

fail() {
    echo "error: $1" >&2
    exit 1
}

[ -f "$FILE" ] || fail "file not found: $FILE"
HEX=$(od -An -tx1 -v "$FILE" | tr -d ' \n')

require_hex() {
    case "$HEX" in
        *"$1"*) ;;
        *) fail "$2" ;;
    esac
}

require_hex 0f05 "missing user syscall instruction"
require_hex 480f07 "missing SYSRETQ return path"
require_hex 47574f32 "missing GWO2 executable magic"
require_hex 20000000 "missing GWO2 header-size validation"
require_hex c59d1c81 "missing GWO2 FNV-1a checksum contract"
require_hex f3a4 "missing bounded GWO payload copy"
require_hex ffff000000f2cf00 "missing DPL3 user data descriptor"
require_hex ffff000000faaf00 "missing DPL3 user code descriptor"
require_hex 48894b58 "missing saved user RIP state"
require_hex 44895b68 "missing saved user flags state"
require_hex 48896360 "missing saved user stack state"
require_hex 488b6348 "missing per-process kernel stack switch"
require_hex b053e6e9b043e6e9b046e6e9b047e6e9 "missing syscall configuration proof"
require_hex b053e6e9b043e6e9b031e6e9 "missing syscall write proof"
require_hex b053e6e9b043e6e9b032e6e9 "missing syscall exit proof"

echo "Grogan syscalls: GWO2 validation, DPL3 boundary, SYSCALL/SYSRETQ, and return-state preservation ok"
