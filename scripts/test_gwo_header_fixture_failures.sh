#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_gwo_header_fixtures.sh"
SOURCE_FIXTURES="$ROOT/fixtures/gwo-header"
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

copy_fixture_root() {
    local name=$1
    local copy_root="$TMP_DIR/$name"

    mkdir -p "$copy_root"
    cp -R "$SOURCE_FIXTURES" "$copy_root/gwo-header"
    printf '%s' "$copy_root/gwo-header"
}

expect_validator_failure() {
    local name=$1
    local expected=$2
    local fixture_root
    local out="$TMP_DIR/$name.out"
    local err="$TMP_DIR/$name.err"

    fixture_root=$(copy_fixture_root "$name")

    case "$name" in
        manifest-lie)
            sed -i 's/^magic=.*/magic=00000000/' "$fixture_root/valid-minimal/manifest.txt"
            ;;
        duplicate-key)
            printf '%s\n' 'magic=47524f00' >> "$fixture_root/valid-minimal/manifest.txt"
            ;;
        unknown-key)
            printf '%s\n' 'loader_accepts=true' >> "$fixture_root/valid-minimal/manifest.txt"
            ;;
        bad-candidate-path)
            sed -i 's/^candidate_hex=.*/candidate_hex=..\/candidate.gwo.hex/' "$fixture_root/valid-minimal/manifest.txt"
            ;;
        blank-line)
            printf '\n' >> "$fixture_root/valid-minimal/manifest.txt"
            ;;
        malformed-line)
            printf '%s\n' 'loader_accepts true' >> "$fixture_root/valid-minimal/manifest.txt"
            ;;
        malformed-hex)
            printf '%s\n' 'zz' > "$fixture_root/valid-minimal/candidate.gwo.hex"
            ;;
        odd-hex)
            printf '%s\n' '0' > "$fixture_root/valid-minimal/candidate.gwo.hex"
            ;;
        bad-expected-result)
            sed -i 's/^expected_result=.*/expected_result=maybe/' "$fixture_root/valid-minimal/manifest.txt"
            ;;
        accept-with-error)
            sed -i 's/^expected_error=.*/expected_error=magic/' "$fixture_root/valid-minimal/manifest.txt"
            ;;
        reject-with-none)
            sed -i 's/^expected_error=.*/expected_error=none/' "$fixture_root/bad-magic/manifest.txt"
            ;;
        missing-required-fixture)
            rm -rf "$fixture_root/unknown-profile"
            ;;
        *)
            fail "unknown negative fixture test: $name"
            ;;
    esac

    if GWO_HEADER_SELF_TEST=1 GWO_HEADER_FIXTURE_ROOT="$fixture_root" "$VALIDATOR" > "$out" 2> "$err"; then
        fail "$name: expected validator failure"
    fi

    grep -F "$expected" "$err" > /dev/null || {
        echo "stdout:" >&2
        cat "$out" >&2
        echo "stderr:" >&2
        cat "$err" >&2
        fail "$name: expected error containing '$expected'"
    }

    pass "$name"
}

bash -n "$VALIDATOR"
pass "validator syntax"

GWO_HEADER_SELF_TEST=1 GWO_HEADER_FIXTURE_ROOT="$SOURCE_FIXTURES" "$VALIDATOR" > /dev/null
pass "baseline fixture root"

if GWO_HEADER_FIXTURE_ROOT="$SOURCE_FIXTURES" "$VALIDATOR" > "$TMP_DIR/env-guard.out" 2> "$TMP_DIR/env-guard.err"; then
    fail "env-guard: expected validator failure"
fi
grep -F "GWO_HEADER_FIXTURE_ROOT is only allowed with GWO_HEADER_SELF_TEST=1" "$TMP_DIR/env-guard.err" > /dev/null || fail "env-guard: wrong failure"
pass "env guard"

expect_validator_failure "manifest-lie" "key magic must be 47524f00, got 00000000"
expect_validator_failure "duplicate-key" "contains duplicate key: magic"
expect_validator_failure "unknown-key" "contains unknown key: loader_accepts"
expect_validator_failure "bad-candidate-path" "candidate_hex must be candidate.gwo.hex"
expect_validator_failure "blank-line" "must not contain blank lines"
expect_validator_failure "malformed-line" "line must use key=value"
expect_validator_failure "malformed-hex" "must contain only hex bytes and whitespace"
expect_validator_failure "odd-hex" "must contain a whole number of bytes"
expect_validator_failure "bad-expected-result" "expected_result must be accept or reject"
expect_validator_failure "accept-with-error" "accepted fixtures must use expected_error=none"
expect_validator_failure "reject-with-none" "rejected fixtures must declare expected_error"
expect_validator_failure "missing-required-fixture" "missing required GWO header fixture: unknown-profile"

echo "passed: $pass_count"
