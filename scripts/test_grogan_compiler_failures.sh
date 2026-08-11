#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
SOURCE="$TMP_DIR/source.grw"
OUT="$TMP_DIR/out.gwo"

fail() { echo "error: $1" >&2; exit 1; }

cp "$ROOT/examples/grown-alpha/hello.grw" "$SOURCE"
"$ROOT/scripts/grc0.sh" "$SOURCE" "$OUT" > /dev/null
echo 'ok: baseline'

sed -i 's/gros\.x86\.bios\.longmode\.grogan\.v1/host.invalid.v1/' "$SOURCE"
if "$ROOT/scripts/grc0.sh" "$SOURCE" "$OUT" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr"; then
    fail 'unsupported-target: expected failure'
fi
grep -F "unsupported target" "$TMP_DIR/stderr" > /dev/null || fail 'unsupported-target: wrong diagnostic'
echo 'ok: unsupported-target'

cp "$ROOT/examples/grown-alpha/hello.grw" "$SOURCE"
sed -i 's/print_i32(total)/print_i32(missing)/' "$SOURCE"
if "$ROOT/scripts/grc0.sh" "$SOURCE" "$OUT" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr"; then
    fail 'unknown-value: expected failure'
fi
grep -F "unknown value" "$TMP_DIR/stderr" > /dev/null || fail 'unknown-value: wrong diagnostic'
echo 'ok: unknown-value'

cp "$ROOT/examples/grown-alpha/hello.grw" "$SOURCE"
sed -i 's/while (i < 8)/while (i < )/' "$SOURCE"
if "$ROOT/scripts/grc0.sh" "$SOURCE" "$OUT" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr"; then
    fail 'syntax: expected failure'
fi
grep -F 'expected integer expression' "$TMP_DIR/stderr" > /dev/null || fail 'syntax: wrong diagnostic'
echo 'ok: syntax'

echo 'Grogan compiler failures: target, name, and syntax diagnostics rejected invalid source'
