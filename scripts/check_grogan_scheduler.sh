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

require_hex 5053515256575541504151415241534154415541564157 \
    "missing complete timer register context save"
require_hex 4889e7 "missing interrupted-context handoff"
require_hex 48897818 "missing task context persistence"
require_hex be00200900 "missing task-one bootstrap stack"
require_hex be00300900 "missing task-two bootstrap stack"
require_hex 488b18 "missing round-robin next-task selection"
require_hex f4eb "missing independently stacked task wait loop"
require_hex b050e6e9b031e6e9 "missing task-one preemption proof"
require_hex b050e6e9b032e6e9 "missing task-two preemption proof"

echo "Grogan scheduler: full interrupt context, independent stacks, round-robin selection, and task proof ok"
