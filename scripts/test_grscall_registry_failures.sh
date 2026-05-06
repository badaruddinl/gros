#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_grscall_registry.sh"
SOURCE_REGISTRY="$ROOT/docs/17-grscall-service-registry.md"
SOURCE_RUNTIME_ABI="$ROOT/scripts/check_runtime_abi.sh"
SOURCE_RUNTIME_ABI_DOC="$ROOT/docs/10-runtime-abi-seed.md"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass_count=0
CASE_REGISTRY=""
CASE_RUNTIME_ABI=""
CASE_RUNTIME_ABI_DOC=""

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
    CASE_RUNTIME_ABI_DOC="$case_root/docs/10-runtime-abi-seed.md"

    cp "$SOURCE_REGISTRY" "$CASE_REGISTRY"
    cp "$SOURCE_RUNTIME_ABI" "$CASE_RUNTIME_ABI"
    cp "$SOURCE_RUNTIME_ABI_DOC" "$CASE_RUNTIME_ABI_DOC"
}

run_self_test_validator() {
    GRSCALL_REGISTRY_SELF_TEST=1 \
        GRSCALL_REGISTRY_DOC="$CASE_REGISTRY" \
        GRSCALL_RUNTIME_ABI_CHECK="$CASE_RUNTIME_ABI" \
        GRSCALL_RUNTIME_ABI_DOC="$CASE_RUNTIME_ABI_DOC" \
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
        wrong-write-crlf-selector)
            sed -i 's/| `01h` | `02h` | `console\/text[.]write_crlf` | implemented |/| `01h` | `03h` | `console\/text.write_crlf` | implemented |/' \
                "$CASE_REGISTRY"
            ;;
        forbidden-candidate-implemented)
            printf '%s\n' '| `00h` | `01h` | `runtime/control.version` | implemented |' \
                >> "$CASE_REGISTRY"
            ;;
        stale-write-crlf-candidate)
            sed -i '/console\/text[.]clear/i | `01h` | `02h` | `console/text.write_crlf` |' \
                "$CASE_REGISTRY"
            ;;
        stale-storage-group-mapping)
            sed -i 's/| `04h` | `storage\/block` | reserved\/future |/| `02h` | `storage\/block` | reserved\/future |/' \
                "$CASE_REGISTRY"
            ;;
        stale-process-group-mapping)
            sed -i 's/| `05h` | `process\/task` | reserved\/future |/| `03h` | `process\/task` | reserved\/future |/' \
                "$CASE_REGISTRY"
            ;;
        missing-memory-seed-candidate)
            grep -v 'memory\/seed[.]probe_map' "$CASE_REGISTRY" > "$CASE_REGISTRY.tmp"
            mv "$CASE_REGISTRY.tmp" "$CASE_REGISTRY"
            ;;
        wrong-boot-info-candidate)
            sed -i 's/| `03h` | `00h` | `boot\/info[.]drive` |/| `03h` | `00h` | `boot\/info.boot_drive` |/' \
                "$CASE_REGISTRY"
            ;;
        missing-runtime-fixture)
            sed -i 's/console\/text write-char service body/console\/text write-char body missing/' \
                "$CASE_RUNTIME_ABI"
            ;;
        missing-crlf-selector-call-fixture)
            sed -i 's/console\/text write-crlf selector call/console\/text write-crlf call missing/' \
                "$CASE_RUNTIME_ABI"
            ;;
        missing-crlf-selector-fixture)
            sed -i 's/console\/text write-crlf selector branch/console\/text write-crlf branch missing/' \
                "$CASE_RUNTIME_ABI"
            ;;
        missing-crlf-preserve-fixture)
            sed -i 's/console\/text write-crlf preserves SI and jumps to success/console\/text write-crlf preserve missing/' \
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
        missing-runtime-abi-registry-reference)
            sed -i 's/docs\/17-grscall-service-registry[.]md/docs\/17-local-service-groups.md/g' \
                "$CASE_RUNTIME_ABI_DOC"
            ;;
        missing-runtime-abi-doc)
            rm -f "$CASE_RUNTIME_ABI_DOC"
            ;;
        missing-runtime-abi-namespace-heading)
            sed -i 's/## GrSCall Service Namespace/## Runtime Service Namespace/' \
                "$CASE_RUNTIME_ABI_DOC"
            ;;
        missing-runtime-abi-write-crlf-service)
            sed -i 's/console\/text[.]write_crlf/console\/text.write_lf/g' \
                "$CASE_RUNTIME_ABI_DOC"
            ;;
        runtime-abi-stale-no-extra-service-claim)
            printf '\n%s\n' 'No other service IDs are implemented yet.' >> "$CASE_RUNTIME_ABI_DOC"
            ;;
        runtime-abi-local-group-table)
            printf '\n%s\n' '## Initial Service Groups' >> "$CASE_RUNTIME_ABI_DOC"
            ;;
        runtime-abi-local-reserved-group-section)
            printf '\n%s\n' '## Reserved Groups' >> "$CASE_RUNTIME_ABI_DOC"
            ;;
        runtime-abi-local-namespace-table)
            {
                printf '\n%s\n' '| Group | Namespace |'
                printf '%s\n' '| --- | --- |'
            } >> "$CASE_RUNTIME_ABI_DOC"
            ;;
        runtime-abi-stale-storage-group)
            printf '\n%s\n' '02h  storage/block' >> "$CASE_RUNTIME_ABI_DOC"
            ;;
        runtime-abi-stale-process-group)
            printf '\n%s\n' '03h  process/task' >> "$CASE_RUNTIME_ABI_DOC"
            ;;
        runtime-abi-stale-memory-group)
            printf '\n%s\n' '04h  memory' >> "$CASE_RUNTIME_ABI_DOC"
            ;;
        runtime-abi-stale-storage-table)
            printf '\n%s\n' '| `02h` | `storage/block` |' >> "$CASE_RUNTIME_ABI_DOC"
            ;;
        runtime-abi-stale-process-table)
            printf '\n%s\n' '| `03h` | `process/task` |' >> "$CASE_RUNTIME_ABI_DOC"
            ;;
        runtime-abi-stale-memory-table)
            printf '\n%s\n' '| `04h` | `memory` |' >> "$CASE_RUNTIME_ABI_DOC"
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
    GRSCALL_RUNTIME_ABI_DOC="$CASE_RUNTIME_ABI_DOC" \
    "$VALIDATOR" > "$TMP_DIR/env-guard.out" 2> "$TMP_DIR/env-guard.err"; then
    fail "env-guard: expected validator failure"
fi
grep -F "GrSCall registry overrides are only allowed with GRSCALL_REGISTRY_SELF_TEST=1" \
    "$TMP_DIR/env-guard.err" > /dev/null || fail "env-guard: wrong failure"
pass "env guard"

expect_validator_failure "missing-implemented-row" "GrSCall registry must list exactly 4 implemented services, got 3"
expect_validator_failure "extra-implemented-service" "GrSCall registry must list exactly 4 implemented services, got 5"
expect_validator_failure "wrong-implemented-selector" "missing console/text.write_char implemented row: | \`01h\` | \`01h\` | \`console/text.write_char\` | implemented |"
expect_validator_failure "wrong-write-crlf-selector" "missing console/text.write_crlf implemented row: | \`01h\` | \`02h\` | \`console/text.write_crlf\` | implemented |"
expect_validator_failure "forbidden-candidate-implemented" "unexpected unimplemented runtime/control.version implemented row: | \`00h\` | \`01h\` | \`runtime/control.version\` | implemented |"
expect_validator_failure "stale-write-crlf-candidate" "unexpected implemented console/text.write_crlf candidate row: | \`01h\` | \`02h\` | \`console/text.write_crlf\` |"
expect_validator_failure "stale-storage-group-mapping" "unexpected registry stale storage/block group assignment: | \`02h\` | \`storage/block\` | reserved/future |"
expect_validator_failure "stale-process-group-mapping" "unexpected registry stale process/task group assignment: | \`03h\` | \`process/task\` | reserved/future |"
expect_validator_failure "missing-memory-seed-candidate" "missing memory/seed.probe_map candidate row: | \`02h\` | \`00h\` | \`memory/seed.probe_map\` |"
expect_validator_failure "wrong-boot-info-candidate" "missing boot/info.drive candidate row: | \`03h\` | \`00h\` | \`boot/info.drive\` |"
expect_validator_failure "missing-runtime-fixture" "missing console/text.write_char runtime ABI fixture: console/text write-char service body"
expect_validator_failure "missing-crlf-selector-call-fixture" "missing console/text.write_crlf runtime ABI fixture: console/text write-crlf selector call"
expect_validator_failure "missing-crlf-selector-fixture" "missing console/text.write_crlf runtime ABI fixture: console/text write-crlf selector branch"
expect_validator_failure "missing-crlf-preserve-fixture" "missing console/text.write_crlf runtime ABI fixture: console/text write-crlf preserves SI and jumps to success"
expect_validator_failure "missing-entry-mechanism" "missing GrSCall real16 entry mechanism: int 30h"
expect_validator_failure "missing-unsupported-carry" "missing unsupported selector carry flag: CF = 1"
expect_validator_failure "missing-validation-reference" "missing runtime ABI validation reference: scripts/check_runtime_abi.sh"
expect_validator_failure "missing-runtime-abi-doc" "missing runtime ABI seed doc:"
expect_validator_failure "missing-runtime-abi-namespace-heading" "missing runtime ABI GrSCall namespace heading: ## GrSCall Service Namespace"
expect_validator_failure "missing-runtime-abi-registry-reference" "missing runtime ABI canonical GrSCall registry reference: docs/17-grscall-service-registry.md"
expect_validator_failure "missing-runtime-abi-write-crlf-service" "missing runtime ABI write_crlf service: console/text.write_crlf"
expect_validator_failure "runtime-abi-stale-no-extra-service-claim" "unexpected runtime ABI stale no-extra-service claim: No other service IDs are implemented yet."
expect_validator_failure "runtime-abi-local-group-table" "unexpected runtime ABI local GrSCall group table: ## Initial Service Groups"
expect_validator_failure "runtime-abi-local-reserved-group-section" "unexpected runtime ABI local reserved group section: ## Reserved Groups"
expect_validator_failure "runtime-abi-local-namespace-table" "unexpected runtime ABI local GrSCall namespace table: | Group | Namespace |"
expect_validator_failure "runtime-abi-stale-storage-group" "unexpected runtime ABI stale storage/block group assignment: 02h  storage/block"
expect_validator_failure "runtime-abi-stale-process-group" "unexpected runtime ABI stale process/task group assignment: 03h  process/task"
expect_validator_failure "runtime-abi-stale-memory-group" "unexpected runtime ABI stale memory group assignment: 04h  memory"
expect_validator_failure "runtime-abi-stale-storage-table" "unexpected runtime ABI stale storage/block table assignment: | \`02h\` | \`storage/block\` |"
expect_validator_failure "runtime-abi-stale-process-table" "unexpected runtime ABI stale process/task table assignment: | \`03h\` | \`process/task\` |"
expect_validator_failure "runtime-abi-stale-memory-table" "unexpected runtime ABI stale memory table assignment: | \`04h\` | \`memory\` |"

echo "passed: $pass_count"
