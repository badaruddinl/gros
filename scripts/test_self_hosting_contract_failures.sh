#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_self_hosting_contracts.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

bash -n "$VALIDATOR"
"$VALIDATOR" > /dev/null

cp -R "$ROOT/contracts/self-hosting-alpha" "$TMP_DIR/contracts"
sed -i '/^loader_requires_checksum=/d' "$TMP_DIR/contracts/gwo2-layout.txt"

if CONTRACTS="$TMP_DIR/contracts" "$VALIDATOR" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
    echo 'error: mutated GWO2 contract was accepted' >&2
    exit 1
fi

grep -F 'loader_requires_checksum=true' "$TMP_DIR/out" "$TMP_DIR/err" > /dev/null || {
    cat "$TMP_DIR/out" >&2
    cat "$TMP_DIR/err" >&2
    echo 'error: missing checksum failure was not reported' >&2
    exit 1
}

cp -R "$ROOT/contracts/self-hosting-alpha" "$TMP_DIR/contracts-task-yield"
sed -i 's/^14[[:space:]]task_yield[[:space:]]0[[:space:]]void[[:space:]]12$/14\ttask_poll\t0\tvoid\t12/' \
    "$TMP_DIR/contracts-task-yield/gwo2-import-abi-v1.tsv"

if CONTRACTS="$TMP_DIR/contracts-task-yield" "$VALIDATOR" > "$TMP_DIR/out-task-yield" 2> "$TMP_DIR/err-task-yield"; then
    echo 'error: task_yield import contract mutation was accepted' >&2
    exit 1
fi

grep -F 'gwo2-import-abi-v1.tsv missing exact line: 14' "$TMP_DIR/err-task-yield" > /dev/null || {
    cat "$TMP_DIR/out-task-yield" >&2
    cat "$TMP_DIR/err-task-yield" >&2
    echo 'error: task_yield mutation was not rejected by the exact-row gate' >&2
    exit 1
}

echo 'self-hosting contract failures: malformed GWO2 contract rejected'
