#!/usr/bin/env bash
set -euo pipefail

# Every ABI column family is mutation-tested.  A contract edit must fail the
# parity checker before it can silently drift one implementation surface.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
fail() { echo "error: $1" >&2; exit 1; }

expect_failure() {
    local label=$1
    if SELF_HOSTING_ABI_CONTRACTS="$TMP_DIR/contracts" SELF_HOSTING_ABI_SKIP_GENERATED=1 \
        "$ROOT/scripts/check_grogan_import_abi_parity.sh" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr"; then
        fail "$label mutation survived ABI parity validation"
    fi
    echo "ok: $label"
}

mkdir -p "$TMP_DIR/contracts"
cp "$ROOT/contracts/self-hosting-alpha/syscall-abi-v1.tsv" "$TMP_DIR/contracts/syscall-abi-v1.tsv"
cp "$ROOT/contracts/self-hosting-alpha/gwo2-import-abi-v1.tsv" "$TMP_DIR/contracts/gwo2-import-abi-v1.tsv"

sed -i '0,/bytes-or-errno/s//zero-or-errno/' "$TMP_DIR/contracts/syscall-abi-v1.tsv"
expect_failure syscall-result
cp "$ROOT/contracts/self-hosting-alpha/syscall-abi-v1.tsv" "$TMP_DIR/contracts/syscall-abi-v1.tsv"

sed -i '0,/0x0f/s//0x0a/' "$TMP_DIR/contracts/syscall-abi-v1.tsv"
expect_failure syscall-selector
cp "$ROOT/contracts/self-hosting-alpha/syscall-abi-v1.tsv" "$TMP_DIR/contracts/syscall-abi-v1.tsv"

sed -i '0,/15\tprocess_spawn\t2/s//15\tprocess_spawn\t3/' "$TMP_DIR/contracts/gwo2-import-abi-v1.tsv"
expect_failure import-argc
cp "$ROOT/contracts/self-hosting-alpha/gwo2-import-abi-v1.tsv" "$TMP_DIR/contracts/gwo2-import-abi-v1.tsv"

sed -i '0,/15\tprocess_spawn\t2\ti32\t15/s//15\tprocess_spawn\t2\ti32\t14/' "$TMP_DIR/contracts/gwo2-import-abi-v1.tsv"
expect_failure import-selector
cp "$ROOT/contracts/self-hosting-alpha/gwo2-import-abi-v1.tsv" "$TMP_DIR/contracts/gwo2-import-abi-v1.tsv"

sed -i '0,/15\tprocess_spawn/s//15\tprocess_spawn_mutated/' "$TMP_DIR/contracts/gwo2-import-abi-v1.tsv"
expect_failure import-name
cp "$ROOT/contracts/self-hosting-alpha/gwo2-import-abi-v1.tsv" "$TMP_DIR/contracts/gwo2-import-abi-v1.tsv"

cp "$ROOT/examples/grown-alpha/grc1.grw" "$TMP_DIR/grc1-mutated.grw"
sed -i 's/if (name_eq(call_name, "task_yield") == 1) { emit8(state, 12); emit8(state, 14); emit8(state, argc); }/if (name_eq(call_name, "task_yield") == 1) { emit8(state, 12); emit8(state, 14); emit8(state, argc); result = 1; }/' "$TMP_DIR/grc1-mutated.grw"
if SELF_HOSTING_ABI_CONTRACTS="$TMP_DIR/contracts" SELF_HOSTING_ABI_GROWN="$TMP_DIR/grc1-mutated.grw" SELF_HOSTING_ABI_SKIP_GENERATED=1 \
    "$ROOT/scripts/check_grogan_import_abi_parity.sh" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr"; then
    fail 'task-yield-result mutation survived ABI parity validation'
fi
grep -aF 'task_yield must remain void' "$TMP_DIR/stderr" > /dev/null || \
    fail 'task-yield-result mutation failed for an unrelated ABI reason'
echo 'ok: task-yield-result'

echo 'Grogan import ABI failures: result, selector, argc, name, mapping, and void-result mutations are rejected'
