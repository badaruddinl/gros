#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-longmode.img"}

fail() {
    echo "error: $1" >&2
    exit 1
}

"$ROOT/scripts/check_longmode_image.sh" "$FILE" > /dev/null

HEX=$(od -An -tx1 -v "$FILE" | tr -d ' \n')
case "$HEX" in
    *b04ce6e9b04de6e9b036e6e9b034e6e9b049e6e9b044e6e9b054e6e9b047e6e9b052e6e9b04fe6e9b036e6e9b034e6e9*)
        ;;
    *)
        fail "missing Grogan x86_64 profile marker"
        ;;
esac

case "$HEX" in
    *e4920c02e692*0f0116*0f22c0*0f22d8*0f22e0*0f30*)
        ;;
    *)
        fail "missing Grogan x86_64 bootstrap transition"
        ;;
esac

case "$HEX" in
    *fc*)
        ;;
    *)
        fail "missing direction-flag normalization"
        ;;
esac

echo "Grogan x86_64 profile: entry, marker, and bootstrap transition ok"
