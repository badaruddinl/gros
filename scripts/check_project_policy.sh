#!/usr/bin/env bash
set -euo pipefail

DEFAULT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ROOT=${PROJECT_POLICY_ROOT:-$DEFAULT_ROOT}

fail() {
    echo "error: $1" >&2
    exit 1
}

if [ -n "${PROJECT_POLICY_ROOT:-}" ] && [ "${PROJECT_POLICY_SELF_TEST:-}" != "1" ]; then
    fail "PROJECT_POLICY_ROOT is only allowed with PROJECT_POLICY_SELF_TEST=1"
fi

require_no_tracked_matches() {
    local name=$1
    shift
    local tracked

    tracked=$(git -C "$ROOT" ls-files "$@" || true)
    [ -z "$tracked" ] || fail "$name must not be tracked:
$tracked"
}

require_no_tracked_regex() {
    local name=$1
    local pattern=$2
    local tracked

    tracked=$(git -C "$ROOT" ls-files | grep -Ei "$pattern" || true)
    [ -z "$tracked" ] || fail "$name must not be tracked:
$tracked"
}

require_no_text_matches() {
    local pattern=$1
    local path_list

    path_list=$(mktemp)

    git -C "$ROOT" ls-files \
        README.md \
        Makefile \
        .gitattributes \
        .gitignore \
        .github \
        boot \
        docs \
        fixtures \
        scripts |
        grep -v '^scripts/check_project_policy[.]sh$' > "$path_list"

    if [ -s "$path_list" ] && (cd "$ROOT" && xargs -r grep -nE "$pattern" < "$path_list"); then
        rm -f "$path_list"
        fail "forbidden public text found"
    fi

    rm -f "$path_list"
}

require_grscall_naming_policy() {
    local path_list
    local matches
    local unexpected
    local legacy_pattern='Gr''Call|gr''call'
    local allowed_naming='^docs/00-naming[.]md:[0-9]+:Deprecated alias: Gr''Call$'
    local allowed_registry='^docs/17-grscall-service-registry[.]md:[0-9]+:future syscall interface[.] `Gr''Call` is a deprecated alias and should not be used$'

    path_list=$(mktemp)

    git -C "$ROOT" ls-files \
        README.md \
        Makefile \
        boot \
        docs \
        fixtures \
        scripts |
        grep -v '^scripts/check_project_policy[.]sh$' > "$path_list"

    matches=$((cd "$ROOT" && xargs -r grep -nE "$legacy_pattern" < "$path_list") || true)
    rm -f "$path_list"

    [ -n "$matches" ] || return

    unexpected=$(
        printf '%s\n' "$matches" |
            grep -vE "$allowed_naming|$allowed_registry" ||
            true
    )

    [ -z "$unexpected" ] || fail "unexpected legacy GrSCall alias public text found:
$unexpected"
}

require_gwo_header_fixture_policy() {
    local file
    local rel

    [ -d "$ROOT/fixtures/gwo-header" ] || return

    while IFS= read -r file; do
        rel=${file#"$ROOT"/}
        case "$rel" in
            fixtures/gwo-header/*/manifest.txt|fixtures/gwo-header/*/candidate.gwo.hex)
                ;;
            *)
                fail "unexpected GWO header fixture file: $rel"
                ;;
        esac
    done < <(find "$ROOT/fixtures/gwo-header" -type f | sort)
}

require_no_tracked_matches "local checkpoint files" ".local/*"
require_no_tracked_matches "generated code-review graph files" ".code-review-graph/*"
require_no_tracked_matches "generated build files" "build/*"
require_no_tracked_matches "Python tooling" "*.py"
require_no_tracked_regex "legacy extension files" '[.](gn|gr|gro)$'
require_no_tracked_regex "roadmap/checkpoint documents" '(^|/)(roadmap|road-map|checkpoints).*\.md$'

FORBIDDEN_TEXT='G''an|v0[.]6|codex/grboot|(^|[^[:alnum:]_])[.](gn|gr|gro)([^[:alnum:]_]|$)'
require_no_text_matches "$FORBIDDEN_TEXT"
require_grscall_naming_policy
require_gwo_header_fixture_policy

echo "project policy: ok"
