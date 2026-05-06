#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_project_policy.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass_count=0
CASE_ROOT=""
BASE_ROOT="$TMP_DIR/base-repo"

pass() {
    pass_count=$((pass_count + 1))
    echo "ok: $1"
}

fail() {
    echo "error: $1" >&2
    exit 1
}

prepare_base_policy_root() {
    local path

    [ -d "$BASE_ROOT/.git" ] && return

    mkdir -p "$BASE_ROOT"

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        mkdir -p "$BASE_ROOT/$(dirname -- "$path")"
        cp "$ROOT/$path" "$BASE_ROOT/$path"
    done < <(git -C "$ROOT" ls-files)

    git -C "$BASE_ROOT" init -q
    git -C "$BASE_ROOT" config core.autocrlf false
    git -C "$BASE_ROOT" config core.safecrlf false
    git -C "$BASE_ROOT" add -A
}

copy_policy_case() {
    local name=$1

    prepare_base_policy_root

    CASE_ROOT="$TMP_DIR/$name/repo"
    mkdir -p "$CASE_ROOT"
    cp -R "$BASE_ROOT/." "$CASE_ROOT"
}

track_case_file() {
    local path=$1

    mkdir -p "$CASE_ROOT/$(dirname -- "$path")"
    [ -f "$CASE_ROOT/$path" ] || printf '%s\n' "fixture" > "$CASE_ROOT/$path"
    git -C "$CASE_ROOT" add -f "$path"
}

run_self_test_validator() {
    PROJECT_POLICY_SELF_TEST=1 \
        PROJECT_POLICY_ROOT="$CASE_ROOT" \
        "$VALIDATOR"
}

append_public_text() {
    local text=$1

    printf '\n%s\n' "$text" >> "$CASE_ROOT/README.md"
}

expect_validator_failure() {
    local name=$1
    local expected=$2
    local out="$TMP_DIR/$name.out"
    local err="$TMP_DIR/$name.err"
    local old_source_ext=".g""n"
    local old_ground_ext=".g""r"
    local old_artifact_ext=".g""ro"
    local old_name="G""an"
    local old_version="v0"".6"
    local old_branch="codex/gr""boot"
    local old_alias="Gr""Call"

    copy_policy_case "$name"

    case "$name" in
        tracked-local)
            track_case_file ".local/roadmap-checkpoints.md"
            ;;
        tracked-code-review-graph)
            track_case_file ".code-review-graph/cache.db"
            ;;
        tracked-build)
            track_case_file "build/generated.gwo"
            ;;
        tracked-python)
            track_case_file "scripts/tool.py"
            ;;
        tracked-legacy-source-ext)
            track_case_file "boot/legacy$old_ground_ext"
            ;;
        tracked-roadmap-doc)
            track_case_file "docs/roadmap-next.md"
            ;;
        forbidden-old-name-text)
            append_public_text "$old_name"
            ;;
        forbidden-version-text)
            append_public_text "$old_version"
            ;;
        forbidden-branch-text)
            append_public_text "$old_branch"
            ;;
        forbidden-source-ext-text)
            append_public_text "legacy source uses $old_source_ext"
            ;;
        forbidden-ground-ext-text)
            append_public_text "legacy ground uses $old_ground_ext"
            ;;
        forbidden-artifact-ext-text)
            append_public_text "legacy artifact uses $old_artifact_ext"
            ;;
        unexpected-legacy-alias-text)
            append_public_text "$old_alias"
            ;;
        unexpected-gwo-header-file)
            mkdir -p "$CASE_ROOT/fixtures/gwo-header/valid-minimal"
            printf '%s\n' "binary fixture" > "$CASE_ROOT/fixtures/gwo-header/valid-minimal/candidate.gwo"
            ;;
        *)
            fail "unknown project policy negative test: $name"
            ;;
    esac

    if run_self_test_validator > "$out" 2> "$err"; then
        fail "$name: expected validator failure"
    fi

    grep -F "$expected" "$out" "$err" > /dev/null || {
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

copy_policy_case "baseline"
run_self_test_validator > /dev/null
pass "baseline policy root"

copy_policy_case "env-guard"
if PROJECT_POLICY_ROOT="$CASE_ROOT" "$VALIDATOR" > "$TMP_DIR/env-guard.out" 2> "$TMP_DIR/env-guard.err"; then
    fail "env-guard: expected validator failure"
fi
grep -F "PROJECT_POLICY_ROOT is only allowed with PROJECT_POLICY_SELF_TEST=1" \
    "$TMP_DIR/env-guard.err" > /dev/null || fail "env-guard: wrong failure"
pass "env guard"

expect_validator_failure "tracked-local" "local checkpoint files must not be tracked:"
expect_validator_failure "tracked-code-review-graph" "generated code-review graph files must not be tracked:"
expect_validator_failure "tracked-build" "generated build files must not be tracked:"
expect_validator_failure "tracked-python" "Python tooling must not be tracked:"
expect_validator_failure "tracked-legacy-source-ext" "legacy extension files must not be tracked:"
expect_validator_failure "tracked-roadmap-doc" "roadmap/checkpoint documents must not be tracked:"
expect_validator_failure "forbidden-old-name-text" "forbidden public text found"
expect_validator_failure "forbidden-version-text" "forbidden public text found"
expect_validator_failure "forbidden-branch-text" "forbidden public text found"
expect_validator_failure "forbidden-source-ext-text" "forbidden public text found"
expect_validator_failure "forbidden-ground-ext-text" "forbidden public text found"
expect_validator_failure "forbidden-artifact-ext-text" "forbidden public text found"
expect_validator_failure "unexpected-legacy-alias-text" "unexpected legacy GrSCall alias public text found:"
expect_validator_failure "unexpected-gwo-header-file" "unexpected GWO header fixture file:"

echo "passed: $pass_count"
