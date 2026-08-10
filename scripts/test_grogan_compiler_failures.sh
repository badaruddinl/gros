#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPILER="$ROOT/scripts/grw_grogan_x86_64.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
SOURCE="$TMP_DIR/source.grw"
OUT="$TMP_DIR/out.gwo"

fail() {
    echo "error: $1" >&2
    exit 1
}

bash -n "$COMPILER"
echo "ok: compiler syntax"
cp "$ROOT/examples/grogan/syscall-smoke.grw" "$SOURCE"
"$COMPILER" "$SOURCE" "$OUT" > /dev/null
echo "ok: baseline"
sed -i 's/grogan::exit()/grogan::unknown()/' "$SOURCE"
if "$COMPILER" "$SOURCE" "$OUT" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
    fail "unsupported-stdlib-call: expected failure"
fi
grep -F "unsupported source" "$TMP_DIR/err" > /dev/null || fail "unsupported-stdlib-call: wrong error"
echo "ok: unsupported-stdlib-call"
