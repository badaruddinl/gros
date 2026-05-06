#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_gwo_artifact_inventory.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass_count=0
CASE_ROOT=""
CASE_LIST=""

pass() {
    pass_count=$((pass_count + 1))
    echo "ok: $1"
}

fail() {
    echo "error: $1" >&2
    exit 1
}

copy_inventory_root() {
    local name=$1
    local path

    CASE_ROOT="$TMP_DIR/$name/root"
    CASE_LIST="$TMP_DIR/$name/inventory.txt"
    mkdir -p "$CASE_ROOT"

    git -C "$ROOT" ls-files '*.gwo' | sort > "$CASE_LIST"

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        mkdir -p "$CASE_ROOT/$(dirname -- "$path")"
        cp "$ROOT/$path" "$CASE_ROOT/$path"
    done < "$CASE_LIST"

    mkdir -p "$CASE_ROOT/fixtures/generated-code/minimal-main-void"
    cp "$ROOT/fixtures/generated-code/minimal-main-void/manifest.txt" \
        "$CASE_ROOT/fixtures/generated-code/minimal-main-void/manifest.txt"
}

run_self_test_validator() {
    GWO_ARTIFACT_INVENTORY_SELF_TEST=1 \
        GWO_ARTIFACT_INVENTORY_ROOT="$CASE_ROOT" \
        GWO_ARTIFACT_INVENTORY_LIST="$CASE_LIST" \
        "$VALIDATOR"
}

expect_validator_failure() {
    local name=$1
    local expected=$2
    local out="$TMP_DIR/$name.out"
    local err="$TMP_DIR/$name.err"

    copy_inventory_root "$name"

    case "$name" in
        unexpected-path)
            mkdir -p "$CASE_ROOT/kernel"
            cp "$CASE_ROOT/dist/gros-v0.5.gwo" "$CASE_ROOT/kernel/rogue.gwo"
            printf '%s\n' 'kernel/rogue.gwo' >> "$CASE_LIST"
            ;;
        header-fixture-binary)
            mkdir -p "$CASE_ROOT/fixtures/gwo-header/valid-minimal"
            cp "$CASE_ROOT/dist/gros-v0.5.gwo" "$CASE_ROOT/fixtures/gwo-header/valid-minimal/candidate.gwo"
            printf '%s\n' 'fixtures/gwo-header/valid-minimal/candidate.gwo' >> "$CASE_LIST"
            ;;
        dist-header-magic)
            printf '\x47\x52\x4f\x00' |
                dd of="$CASE_ROOT/dist/gros-v0.5.gwo" bs=1 count=4 conv=notrunc status=none
            ;;
        missing-required)
            grep -v '^dist/gros-stage2[.]gwo$' "$CASE_LIST" > "$CASE_LIST.tmp"
            mv "$CASE_LIST.tmp" "$CASE_LIST"
            ;;
        generated-not-expected-only)
            sed -i 's/^status=.*/status=compiler-output/' \
                "$CASE_ROOT/fixtures/generated-code/minimal-main-void/manifest.txt"
            ;;
        *)
            fail "unknown inventory negative test: $name"
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

copy_inventory_root "baseline"
run_self_test_validator > /dev/null
pass "baseline inventory root"

copy_inventory_root "env-guard"
if GWO_ARTIFACT_INVENTORY_ROOT="$CASE_ROOT" \
    GWO_ARTIFACT_INVENTORY_LIST="$CASE_LIST" \
    "$VALIDATOR" > "$TMP_DIR/env-guard.out" 2> "$TMP_DIR/env-guard.err"; then
    fail "env-guard: expected validator failure"
fi
grep -F "GWO artifact inventory overrides are only allowed with GWO_ARTIFACT_INVENTORY_SELF_TEST=1" \
    "$TMP_DIR/env-guard.err" > /dev/null || fail "env-guard: wrong failure"
pass "env guard"

expect_validator_failure "unexpected-path" "unexpected tracked GWO artifact: kernel/rogue.gwo"
expect_validator_failure "header-fixture-binary" "headered GWO fixtures must stay reviewable manifest/hex files"
expect_validator_failure "dist-header-magic" "dist/gros-v0.5.gwo must remain a raw-profile artifact without GWO header magic"
expect_validator_failure "missing-required" "required GWO artifact is not tracked: dist/gros-stage2.gwo"
expect_validator_failure "generated-not-expected-only" "must belong to an expected-only generated-code fixture"

echo "passed: $pass_count"
