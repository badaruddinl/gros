#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GRRAW="$ROOT/scripts/grraw.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass_count=0

pass() {
    pass_count=$((pass_count + 1))
    echo "ok: $1"
}

fail() {
    echo "error: $1" >&2
    exit 1
}

hex_prefix() {
    local file=$1
    local bytes=$2
    od -An -tx1 -N "$bytes" "$file" | tr -d ' \n'
}

expect_prefix() {
    local name=$1
    local expected=$2
    local src="$TMP_DIR/$name.gr"
    local out="$TMP_DIR/$name.gro"
    cat > "$src"

    "$GRRAW" "$src" "$out"

    local byte_count=$(( ${#expected} / 2 ))
    local actual
    actual=$(hex_prefix "$out" "$byte_count")
    [ "$actual" = "$expected" ] || fail "$name: expected $expected, got $actual"
    pass "$name"
}

expect_fails() {
    local name=$1
    local message=$2
    local src="$TMP_DIR/$name.gr"
    local out="$TMP_DIR/$name.gro"
    local err="$TMP_DIR/$name.err"
    cat > "$src"

    if "$GRRAW" "$src" "$out" > /dev/null 2> "$err"; then
        fail "$name: expected failure"
    fi
    grep -F "$message" "$err" > /dev/null || fail "$name: expected error containing '$message'"
    pass "$name"
}

bash -n "$ROOT/scripts/grraw.sh" "$ROOT/scripts/build_boot.sh" "$ROOT/scripts/check_boot.sh" "$ROOT/scripts/run_qemu.sh"
pass "shell syntax"

expect_prefix "addr16" "be037c00" <<'GR'
origin 7C00
bytes BE
addr16 banner
label banner
byte 00
GR

expect_prefix "rel8-forward" "eb019000" <<'GR'
origin 7C00
bytes EB
rel8 done
byte 90
label done
byte 00
GR

expect_prefix "rel8-backward" "90ebfd" <<'GR'
origin 7C00
label loop
byte 90
bytes EB
rel8 loop
GR

expect_prefix "rel16-forward" "e801009000" <<'GR'
origin 7C00
bytes E8
rel16 target
byte 90
label target
byte 00
GR

expect_prefix "ascii-semicolon" "413b4200" <<'GR'
ascii "A;B"
byte 00
GR

process_out="$TMP_DIR/process-substitution.gro"
"$GRRAW" <(printf '%s\n' 'origin 7C00' 'ascii "PS"' 'byte 00') "$process_out"
[ "$(hex_prefix "$process_out" 3)" = "505300" ] || fail "process-substitution: wrong output"
pass "process substitution source"

expect_fails "duplicate-label" "duplicate label" <<'GR'
label same
label same
GR

expect_fails "unknown-label" "unknown label" <<'GR'
bytes E8
rel16 missing
GR

expect_fails "late-origin" "origin must appear before labels or emitted bytes" <<'GR'
byte 00
origin 7C00
GR

expect_fails "origin-after-label" "origin must appear before labels or emitted bytes" <<'GR'
label before
origin 7C00
GR

expect_fails "rel8-range" "relative target out of range" <<'GR'
bytes EB
rel8 far
pad_to 200 with 00
label far
byte 00
GR

"$ROOT/scripts/build_boot.sh" > /dev/null
"$ROOT/scripts/check_boot.sh" > /dev/null
"$ROOT/scripts/check_boot.sh" "$ROOT/dist/gros-v0.4.gro" > /dev/null
cmp -s "$ROOT/build/gros-v0.4.gro" "$ROOT/dist/gros-v0.4.gro" || fail "v0.4 build differs from dist artifact"
pass "v0.4 artifact"

echo "passed: $pass_count"
