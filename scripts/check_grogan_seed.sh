#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-stage2.gwo"}
fail() { echo "error: $1" >&2; exit 1; }
[ -f "$FILE" ] || fail "file not found: $FILE"
grep -F 'label grogan_entry' "$ROOT/boot/stage2_min.gwn" > /dev/null || fail "missing Grogan entry label"
grep -F 'label grogan_grscall_handler' "$ROOT/boot/stage2_min.gwn" > /dev/null || fail "Grogan must own GrSCall handler"
grep -F 'label grogan_state_magic' "$ROOT/boot/stage2_min.gwn" > /dev/null || fail "missing Grogan state magic"
HEX=$(dd if="$FILE" bs=1 skip=544 count=2016 2> /dev/null | od -An -tx1 -v | tr -d ' \n')
case "$HEX" in *4752474e*) ;; *) fail "missing Grogan state magic bytes";; esac
case "$HEX" in *c706*0100*) ;; *) fail "missing Grogan state initialization";; esac
echo "grogan seed: entry, state, and GrSCall ownership ok"
