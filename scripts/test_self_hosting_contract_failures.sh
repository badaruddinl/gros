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

echo 'self-hosting contract failures: malformed GWO2 contract rejected'
