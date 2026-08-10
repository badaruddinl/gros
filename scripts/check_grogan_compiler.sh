#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE=${1:-"$ROOT/examples/grogan/syscall-smoke.grw"}
GWO=${2:-"$ROOT/build/generated/grogan-user.gwo"}
IMAGE=${3:-"$ROOT/build/gros-longmode.img"}

fail() {
    echo "error: $1" >&2
    exit 1
}

[ -f "$SOURCE" ] || fail "source file not found: $SOURCE"
"$ROOT/scripts/grw_grogan_x86_64.sh" "$SOURCE" "$GWO" > /dev/null
[ "$(wc -c < "$GWO" | tr -d ' ')" = 41 ] || fail "compiler must emit a 41-byte bounded GWO1 artifact"
[ "$(dd if="$GWO" bs=1 skip=0 count=4 2> /dev/null | od -An -tx1 -v | tr -d ' \n')" = 47574f31 ] || fail "compiler artifact magic must be GWO1"
[ "$(dd if="$GWO" bs=1 skip=12 count=4 2> /dev/null | od -An -tx1 -v | tr -d ' \n')" = 11000000 ] || fail "compiler artifact payload size must be 17 bytes"
[ "$(dd if="$GWO" bs=1 skip=20 count=4 2> /dev/null | od -An -tx1 -v | tr -d ' \n')" = 77040000 ] || fail "compiler artifact checksum must match generated payload"

"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
GWO_HEX=$(od -An -tx1 -v "$GWO" | tr -d ' \n')
IMAGE_HEX=$(od -An -tx1 -v "$IMAGE" | tr -d ' \n')
case "$IMAGE_HEX" in
    *"$GWO_HEX"*) ;;
    *) fail "long-mode image does not embed the compiler-produced GWO artifact" ;;
esac

echo "Grogan compiler: target grammar, stdlib syscall lowering, GWO1 checksum, and image embedding ok"
