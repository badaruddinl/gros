#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_generated_fixtures.sh"
SOURCE_FIXTURES="$ROOT/fixtures/generated-code"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass_count=0
CASE_ROOT=""
CASE_FIXTURE=""

pass() {
    pass_count=$((pass_count + 1))
    echo "ok: $1"
}

fail() {
    echo "error: $1" >&2
    exit 1
}

copy_generated_case() {
    local name=$1

    CASE_ROOT="$TMP_DIR/$name/generated-code"
    mkdir -p "$(dirname -- "$CASE_ROOT")"
    cp -R "$SOURCE_FIXTURES" "$CASE_ROOT"
    CASE_FIXTURE="$CASE_ROOT/minimal-main-void"
}

run_self_test_validator() {
    GENERATED_FIXTURES_SELF_TEST=1 \
        GENERATED_FIXTURES_ROOT="$CASE_ROOT" \
        "$VALIDATOR"
}

expect_validator_failure() {
    local name=$1
    local expected=$2
    local out="$TMP_DIR/$name.out"
    local err="$TMP_DIR/$name.err"

    copy_generated_case "$name"

    case "$name" in
        missing-manifest)
            rm -f "$CASE_FIXTURE/manifest.txt"
            ;;
        missing-name)
            sed -i '/^name=/d' "$CASE_FIXTURE/manifest.txt"
            ;;
        name-mismatch)
            sed -i 's/^name=.*/name=wrong-name/' "$CASE_FIXTURE/manifest.txt"
            ;;
        duplicate-key)
            printf '%s\n' 'profile=gros.x86.bios.real16.stage2.v0' >> "$CASE_FIXTURE/manifest.txt"
            ;;
        unknown-key)
            printf '%s\n' 'compiler_output=true' >> "$CASE_FIXTURE/manifest.txt"
            ;;
        blank-line)
            printf '\n' >> "$CASE_FIXTURE/manifest.txt"
            ;;
        malformed-line)
            printf '%s\n' 'source source.grw' >> "$CASE_FIXTURE/manifest.txt"
            ;;
        profile-mismatch)
            sed -i 's/^profile=.*/profile=host.linux.x86_64.v0/' "$CASE_FIXTURE/manifest.txt"
            ;;
        status-mismatch)
            sed -i 's/^status=.*/status=compiler-output/' "$CASE_FIXTURE/manifest.txt"
            ;;
        wrong-source-name)
            sed -i 's/^source=.*/source=main.grw/' "$CASE_FIXTURE/manifest.txt"
            ;;
        missing-source-file)
            rm -f "$CASE_FIXTURE/source.grw"
            ;;
        missing-expected-gwn-file)
            rm -f "$CASE_FIXTURE/expected.gwn"
            ;;
        missing-expected-gwo-file)
            rm -f "$CASE_FIXTURE/expected.gwo"
            ;;
        bad-expected-size-format)
            sed -i 's/^expected_size=.*/expected_size=2kb/' "$CASE_FIXTURE/manifest.txt"
            ;;
        bad-expected-size-value)
            sed -i 's/^expected_size=.*/expected_size=1024/' "$CASE_FIXTURE/manifest.txt"
            ;;
        unsupported-entry-address)
            sed -i 's/^entry_address=.*/entry_address=0000:9000/' "$CASE_FIXTURE/manifest.txt"
            ;;
        missing-entry-address)
            sed -i '/^entry_address=/d' "$CASE_FIXTURE/manifest.txt"
            ;;
        missing-source-target)
            sed -i '/^target /d' "$CASE_FIXTURE/source.grw"
            ;;
        target-comment-only)
            sed -i 's/^target /\/\/ target /' "$CASE_FIXTURE/source.grw"
            ;;
        source-embeds-raw)
            printf '\n%s\n' 'raw x86.bios.real16.generated.minimal_main_void {' >> "$CASE_FIXTURE/source.grw"
            ;;
        expected-missing-raw)
            sed -i 's/^raw /boundary /' "$CASE_FIXTURE/expected.gwn"
            ;;
        wrong-raw-boundary)
            sed -i 's/raw x86[.]bios[.]real16[.]generated[.]minimal_main_void/raw x86.bios.real16.generated.other/' \
                "$CASE_FIXTURE/expected.gwn"
            ;;
        wrong-origin)
            sed -i 's/origin 8000/origin 9000/' "$CASE_FIXTURE/expected.gwn"
            ;;
        expected-gwo-wrong-size)
            truncate -s 1024 "$CASE_FIXTURE/expected.gwo"
            ;;
        expected-gwo-parity)
            printf '\x90' | dd of="$CASE_FIXTURE/expected.gwo" bs=1 seek=0 count=1 conv=notrunc status=none
            ;;
        * )
            fail "unknown generated fixture negative test: $name"
            ;;
    esac

    if run_self_test_validator > "$out" 2> "$err"; then
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

copy_generated_case "baseline"
run_self_test_validator > /dev/null
pass "baseline generated fixture root"

copy_generated_case "env-guard"
if GENERATED_FIXTURES_ROOT="$CASE_ROOT" "$VALIDATOR" > "$TMP_DIR/env-guard.out" 2> "$TMP_DIR/env-guard.err"; then
    fail "env-guard: expected validator failure"
fi
grep -F "GENERATED_FIXTURES_ROOT is only allowed with GENERATED_FIXTURES_SELF_TEST=1" \
    "$TMP_DIR/env-guard.err" > /dev/null || fail "env-guard: wrong failure"
pass "env guard"

expect_validator_failure "missing-manifest" "fixture missing manifest:"
expect_validator_failure "missing-name" "missing key: name"
expect_validator_failure "name-mismatch" "key name must be minimal-main-void, got wrong-name"
expect_validator_failure "duplicate-key" "contains duplicate key: profile"
expect_validator_failure "unknown-key" "contains unknown key: compiler_output"
expect_validator_failure "blank-line" "must not contain blank lines"
expect_validator_failure "malformed-line" "line must use key=value: source source.grw"
expect_validator_failure "profile-mismatch" "key profile must be gros.x86.bios.real16.stage2.v0, got host.linux.x86_64.v0"
expect_validator_failure "status-mismatch" "key status must be expected-only, got compiler-output"
expect_validator_failure "wrong-source-name" "key source must be source.grw, got main.grw"
expect_validator_failure "missing-source-file" "fixture missing file declared by source:"
expect_validator_failure "missing-expected-gwn-file" "fixture missing file declared by expected_gwn:"
expect_validator_failure "missing-expected-gwo-file" "fixture missing file declared by expected_gwo:"
expect_validator_failure "bad-expected-size-format" "key expected_size must be decimal bytes, got 2kb"
expect_validator_failure "bad-expected-size-value" "key expected_size must be 2048, got 1024"
expect_validator_failure "unsupported-entry-address" "key entry_address must be 0000:8000, got 0000:9000"
expect_validator_failure "missing-entry-address" "missing key: entry_address"
expect_validator_failure "missing-source-target" "must declare target gros.x86.bios.real16.stage2.v0"
expect_validator_failure "target-comment-only" "must declare target gros.x86.bios.real16.stage2.v0"
expect_validator_failure "source-embeds-raw" "must stay informational and must not embed raw ground code"
expect_validator_failure "expected-missing-raw" "must be raw .gwn source"
expect_validator_failure "wrong-raw-boundary" "must declare raw x86.bios.real16.generated.minimal_main_void"
expect_validator_failure "wrong-origin" "origin must match entry_address 0000:8000"
expect_validator_failure "expected-gwo-wrong-size" "must be 2048 bytes, got 1024"
expect_validator_failure "expected-gwo-parity" "expected.gwo must match expected.gwn build output"

echo "passed: $pass_count"
