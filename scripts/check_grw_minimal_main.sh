#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE=${1:-"$ROOT/examples/generated/minimal-main-void.grw"}
GWN=${2:-"$ROOT/build/generated/minimal-main-void.gwn"}
IMAGE=${3:-"$ROOT/build/generated/minimal-main-void.gwo"}

fail() { echo "error: $1" >&2; exit 1; }

[ -f "$SOURCE" ] || fail "source file not found: $SOURCE"
[ -f "$GWN" ] || fail "compiler output not found: $GWN"
[ -f "$IMAGE" ] || fail "image not found: $IMAGE"

grep -F 'origin 8020' "$GWN" > /dev/null || fail "compiler output must originate at 8020"
grep -F 'pad_to 2016 with 00' "$GWN" > /dev/null || fail "compiler output must reserve 2016 bytes"
HEADER=$(dd if="$IMAGE" bs=1 skip=512 count=32 2> /dev/null | od -An -tx1 -v | tr -d ' \n')
[ "$HEADER" = '47524f00200000000000000000000000e0070000000000000000000000000000' ] || fail "image must contain the fixed stage-2 header"
ENTRY=$(dd if="$IMAGE" bs=1 skip=544 count=4 2> /dev/null | od -An -tx1 -v | tr -d ' \n')
[ "$ENTRY" = 'faf4ebfc' ] || fail "compiled main must halt at payload entry"
"$ROOT/scripts/check_headered_stage2_loader.sh" "$IMAGE" > /dev/null
echo "minimal main: compiler output and headered image ok"
