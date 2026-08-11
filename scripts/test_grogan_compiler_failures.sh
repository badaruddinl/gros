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

cp "$ROOT/examples/grown-alpha/module-main.grw" "$SOURCE"
sed -i 's/module-math\.grw/module-missing\.grw/' "$SOURCE"
if "$ROOT/scripts/grc0.sh" "$SOURCE" "$OUT" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr"; then
    fail 'missing-module: expected failure'
fi
grep -F 'cannot read source' "$TMP_DIR/stderr" > /dev/null || fail 'missing-module: wrong diagnostic'
echo 'ok: missing-module'

cp "$ROOT/examples/grown-alpha/module-main.grw" "$SOURCE"
sed -i 's/import "module-math.grw";/import module-math.grw;/' "$SOURCE"
if "$ROOT/scripts/grc0.sh" "$SOURCE" "$OUT" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr"; then
    fail 'malformed-import: expected failure'
fi
grep -F 'quoted module path' "$TMP_DIR/stderr" > /dev/null || fail 'malformed-import: wrong diagnostic'
echo 'ok: malformed-import'

cp "$ROOT/examples/grown-alpha/module-main.grw" "$SOURCE"
sed -i 's|import "module-math.grw";|import "../module-math.grw";|' "$SOURCE"
if "$ROOT/scripts/grc0.sh" "$SOURCE" "$OUT" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr"; then
    fail 'root-import: expected failure'
fi
grep -F 'bounded root filename' "$TMP_DIR/stderr" > /dev/null || fail 'root-import: wrong diagnostic'
echo 'ok: root-import'

echo 'Grogan compiler failures: target, module, name, and syntax diagnostics rejected invalid source'
