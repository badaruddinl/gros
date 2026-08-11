#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-longmode.img"}

fail() { echo "error: $1" >&2; exit 1; }
"$ROOT/scripts/check_longmode_image.sh" "$FILE" > /dev/null
HEX=$(od -An -tx1 -v "$FILE" | tr -d ' \n')
require_hex() {
    case "$HEX" in *"$1"*) ;; *) fail "$2" ;; esac
}

require_hex 0f00d8 "missing hardware TSS load"
require_hex 488b0425 "missing per-process CR3 load"
require_hex 48894310 "missing owned user page-table root"
require_hex 488903 "missing user PTE installation"
require_hex 48894b58 "missing per-process syscall RIP save"
require_hex 488b6348 "missing per-process kernel-stack switch"
require_hex 4881ff00004000 "missing user-pointer lower bound"
require_hex 4981ea00004000 "missing user-pointer page walk"
require_hex b050e6e9b046e6e9 "missing recoverable user page-fault marker"
require_hex 48897b50 "missing timer context ownership handoff"
require_hex 498b442450 "missing next process context resume"
require_hex 46524d31 "missing frame ownership seed"

echo "Grogan processes: TSS, owned CR3/PT roots, user-span validation, timer contexts, and recoverable faults ok"
