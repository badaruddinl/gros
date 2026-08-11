#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RUSTC=${RUSTC:-rustc}
GRVM_LIMIT=${GRVM_LIMIT:-100000000}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "error: $1" >&2; exit 1; }

command -v "$RUSTC" > /dev/null 2>&1 || fail "${RUSTC} is required"
command -v cc > /dev/null 2>&1 || fail 'cc is required for the host verifier/VM'

SOURCE="$ROOT/examples/grown-alpha/grc1.grw"
"$ROOT/scripts/grc0.sh" "$SOURCE" "$TMP_DIR/grc1.gwo"
cp "$SOURCE" "$TMP_DIR/grc1.grw"

(
    cd "$TMP_DIR"
    "$ROOT/scripts/grvm.sh" grc1.gwo "$GRVM_LIMIT"
    [ -s grc2.gwo ] || fail 'Grown compiler did not emit grc2.gwo'
    "$ROOT/scripts/grvm.sh" grc2.gwo "$GRVM_LIMIT"
    cp grc2.gwo grc2-first.gwo
    "$ROOT/scripts/grvm.sh" grc2.gwo "$GRVM_LIMIT"
    cmp -s grc2-first.gwo grc2.gwo || fail 'Grown compiler did not reach a byte-stable fixed point'
)

SHA256=$(sha256sum "$TMP_DIR/grc2.gwo" | awk '{print $1}')
echo "Grogan self-host: Rust bootstrap, in-VM Grown rebuild, and fixed point ok (${SHA256})"
