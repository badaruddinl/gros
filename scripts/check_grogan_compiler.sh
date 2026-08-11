#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE=${1:-"$ROOT/examples/grown-alpha/hello.grw"}
GWO=${2:-"$ROOT/build/generated/grogan-user.gwo"}
IMAGE=${3:-"$ROOT/build/gros-longmode.img"}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "error: $1" >&2; exit 1; }

[ -f "$SOURCE" ] || fail "source file not found: $SOURCE"
"$ROOT/scripts/grc0.sh" "$SOURCE" "$GWO"
"$ROOT/scripts/grc0.sh" "$SOURCE" "$TMP_DIR/repeat.gwo"
cmp -s "$GWO" "$TMP_DIR/repeat.gwo" || fail "GWO2 compiler output is not deterministic"
[ "$(dd if="$GWO" bs=1 skip=0 count=4 2> /dev/null | od -An -tx1 -v | tr -d ' \n')" = 47574f32 ] || fail "compiler artifact magic must be GWO2"
[ "$(dd if="$GWO" bs=1 skip=12 count=4 2> /dev/null | od -An -tx1 -v | tr -d ' \n')" = 20000000 ] || fail "compiler header size must be 32 bytes"
[ "$(dd if="$GWO" bs=1 skip=16 count=4 2> /dev/null | od -An -tx1 -v | tr -d ' \n')" = 01000000 ] || fail "compiler section count must be one"
[ "$("$ROOT/scripts/grvm.sh" "$GWO")" = 28 ] || fail "host GrVM output must be 28"

"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
GWO_HEX=$(od -An -tx1 -v "$GWO" | tr -d ' \n')
IMAGE_HEX=$(od -An -tx1 -v "$IMAGE" | tr -d ' \n')
case "$IMAGE_HEX" in
    *"$GWO_HEX"*) ;;
    *) fail "long-mode image does not embed the compiler-produced GWO2 artifact" ;;
esac

echo "Grogan compiler: Grown parser, deterministic GWO2 lowering, host VM, and image embedding ok"
