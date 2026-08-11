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

ID31=$(printf '%031d' 0 | tr '0' a)
cat > "$SOURCE" <<EOF
target "gros.x86.bios.longmode.grogan.v1"
fn $ID31() -> void {}
fn main() -> void { $ID31(); }
EOF
"$ROOT/scripts/grc0.sh" "$SOURCE" "$OUT" > /dev/null || fail 'identifier-31: maximum identifier should compile'
echo 'ok: identifier-31'

ID32=${ID31}a
sed "s/$ID31/$ID32/g" "$SOURCE" > "$TMP_DIR/identifier-too-long.grw"
if "$ROOT/scripts/grc0.sh" "$TMP_DIR/identifier-too-long.grw" "$OUT" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr"; then
    fail 'identifier-32: expected failure'
fi
grep -F 'identifier is too long' "$TMP_DIR/stderr" > /dev/null || fail 'identifier-32: wrong diagnostic'
echo 'ok: identifier-32'

STRING255=$(printf '%0255d' 0 | tr '0' s)
cat > "$SOURCE" <<EOF
target "gros.x86.bios.longmode.grogan.v1"
fn main() -> void { print_str("$STRING255"); }
EOF
"$ROOT/scripts/grc0.sh" "$SOURCE" "$OUT" > /dev/null || fail 'string-255: maximum byte string should compile'
echo 'ok: string-255'

STRING256=${STRING255}s
sed "s/$STRING255/$STRING256/" "$SOURCE" > "$TMP_DIR/string-too-long.grw"
if "$ROOT/scripts/grc0.sh" "$TMP_DIR/string-too-long.grw" "$OUT" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr"; then
    fail 'string-256: expected failure'
fi
grep -F 'byte string is too long' "$TMP_DIR/stderr" > /dev/null || fail 'string-256: wrong diagnostic'
echo 'ok: string-256'

# Mutation tests keep the negative lane honest: if either Grown guard is
# weakened, the exact boundary corpus must stop passing instead of silently
# producing a wrapped artifact.  The mutated compiler is executed by the
# reference GrVM so this check does not rely on the Rust parser under test.
run_mutation_guard() {
    local label=$1
    local pattern=$2
    local replacement=$3
    local edge_source=$4
    local mutation_dir="$TMP_DIR/mutation-$label"
    mkdir -p "$mutation_dir"
    cp "$ROOT/examples/grown-alpha/grc1.grw" "$mutation_dir/grc1-source.grw"
    sed -i "0,/$pattern/s//$replacement/" "$mutation_dir/grc1-source.grw"
    "$ROOT/scripts/grc0.sh" "$mutation_dir/grc1-source.grw" "$mutation_dir/grc1.gwo" > /dev/null
    cp "$edge_source" "$mutation_dir/grc1.grw"
    (
        cd "$mutation_dir"
        set +e
        "$ROOT/scripts/grvm.sh" grc1.gwo > stdout 2> stderr
        status=$?
        set -e
        # A surviving guard mutation must accept the invalid edge.  That is
        # the signal this mutation test needs: the surrounding boundary
        # assertion would reject this status/artifact pair.
        [ "$status" -eq 0 ] || exit 1
        [ -s grc2.gwo ] || exit 1
    ) || fail "$label mutation survived: the boundary lane no longer distinguishes the invalid edge"
    echo "ok: $label-mutation"
}

cat > "$TMP_DIR/identifier-edge.grw" <<EOF
target "gros.x86.bios.longmode.grogan.v1"
fn $ID32() -> void {}
fn main() -> void { $ID32(); }
EOF
run_mutation_guard identifier-bound "if (index < 31)" "if (index < 255)" "$TMP_DIR/identifier-edge.grw"

cat > "$TMP_DIR/string-edge.grw" <<EOF
target "gros.x86.bios.longmode.grogan.v1"
fn main() -> void { print_str("$STRING256"); }
EOF
run_mutation_guard string-bound "if (index < 255)" "if (index < 256)" "$TMP_DIR/string-edge.grw"

echo 'Grogan compiler failures: target, module, name, and syntax diagnostics rejected invalid source'
