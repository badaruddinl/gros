#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_grscall_registry.sh"
SOURCE_REGISTRY="$ROOT/docs/17-grscall-service-registry.md"
SOURCE_RUNTIME_ABI="$ROOT/scripts/check_runtime_abi.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass_count=0
CASE_REGISTRY=""
CASE_RUNTIME_ABI=""

pass() {
    pass_count=$((pass_count + 1))
    echo "ok: $1"
}

fail() {
    echo "error: $1" >&2
    exit 1
}

copy_registry_case() {
    local name=$1
    local case_root="$TMP_DIR/$name"

    mkdir -p "$case_root/docs" "$case_root/scripts"
    CASE_REGISTRY="$case_root/docs/17-grscall-service-registry.md"
    CASE_RUNTIME_ABI="$case_root/scripts/check_runtime_abi.sh"

    cp "$SOURCE_REGISTRY" "$CASE_REGISTRY"
    cp "$SOURCE_RUNTIME_ABI" "$CASE_RUNTIME_ABI"
}

run_self_test_validator() {
    GRSCALL_REGISTRY_SELF_TEST=1 \
        GRSCALL_REGISTRY_DOC="$CASE_REGISTRY" \
        GRSCALL_RUNTIME_ABI_CHECK="$CASE_RUNTIME_ABI" \
        "$VALIDATOR"
}

expect_validator_failure() {
    local name=$1
    local expected=$2
    local out="$TMP_DIR/$name.out"
    local err="$TMP_DIR/$name.err"

    copy_registry_case "$name"

    case "$name" in
        missing-implemented-row)
            grep -v 'runtime/control[.]probe' "$CASE_REGISTRY" > "$CASE_REGISTRY.tmp"
            mv "$CASE_REGISTRY.tmp" "$CASE_REGISTRY"
            ;;
        extra-implemented-service)
            sed -i '/runtime\/control[.]probe/a | `00h` | `01h` | `runtime/control.version` | implemented |' \
                "$CASE_REGISTRY"
            ;;
        wrong-implemented-selector)
            sed -i 's/| `01h` | `01h` | `console\/text[.]write_char` | implemented |/| `01h` | `02h` | `console\/text.write_char` | implemented |/' \
                "$CASE_REGISTRY"
            ;;
        forbidden-candidate-implemented)
            printf '%s\n' '| `00h` | `01h` | `runtime/control.version` | implemented |' \
                >> "$CASE_REGISTRY"
            ;;
        missing-runtime-fixture)
            sed -i 's/console\/text write-char service body/console\/text write-char body missing/' \
                "$CASE_RUNTIME_ABI"
            ;;
        missing-entry-mechanism)
            sed -i 's/int 30h/int 31h/g' "$CASE_REGISTRY"
            ;;
        missing-unsupported-carry)
            sed -i 's/CF = 1/CF = ?/g' "$CASE_REGISTRY"
            ;;
        missing-validation-reference)
            sed -i 's/scripts\/check_runtime_abi[.]sh/scripts\/check_runtime_contract.sh/g' \
                "$CASE_REGISTRY"
            ;;
        *)
            fail "unknown GrSCall registry negative test: $name"
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

copy_registry_case "baseline"
run_self_test_validator > /dev/null
pass "baseline registry root"

copy_registry_case "env-guard"
if GRSCALL_REGISTRY_DOC="$CASE_REGISTRY" \
    GRSCALL_RUNTIME_ABI_CHECK="$CASE_RUNTIME_ABI" \
    "$VALIDATOR" > "$TMP_DIR/env-guard.out" 2> "$TMP_DIR/env-guard.err"; then
    fail "env-guard: expected validator failure"
fi
grep -F "GrSCall registry overrides are only allowed with GRSCALL_REGISTRY_SELF_TEST=1" \
    "$TMP_DIR/env-guard.err" > /dev/null || fail "env-guard: wrong failure"
pass "env guard"

expect_validator_failure "missing-implemented-row" "GrSCall registry must list exactly 3 implemented services, got 2"
expect_validator_failure "extra-implemented-service" "GrSCall registry must list exactly 3 implemented services, got 4"
expect_validator_failure "wrong-implemented-selector" "missing console/text.write_char implemented row: | \`01h\` | \`01h\` | \`console/text.write_char\` | implemented |"
expect_validator_failure "forbidden-candidate-implemented" "unexpected unimplemented runtime/control.version implemented row: | \`00h\` | \`01h\` | \`runtime/control.version\` | implemented |"
expect_validator_failure "missing-runtime-fixture" "missing console/text.write_char runtime ABI fixture: console/text write-char service body"
expect_validator_failure "missing-entry-mechanism" "missing GrSCall real16 entry mechanism: int 30h"
expect_validator_failure "missing-unsupported-carry" "missing unsupported selector carry flag: CF = 1"
expect_validator_failure "missing-validation-reference" "missing runtime ABI validation reference: scripts/check_runtime_abi.sh"

echo "passed: $pass_count"
