#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

fail() {
    echo "error: $1" >&2
    exit 1
}

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
        scripts |
        grep -v '^scripts/check_project_policy[.]sh$' > "$path_list"

    if [ -s "$path_list" ] && xargs -r grep -nE "$pattern" < "$path_list"; then
        rm -f "$path_list"
        fail "forbidden public text found"
    fi

    rm -f "$path_list"
}

require_no_tracked_matches "local checkpoint files" ".local/*"
require_no_tracked_matches "generated code-review graph files" ".code-review-graph/*"
require_no_tracked_matches "generated build files" "build/*"
require_no_tracked_matches "Python tooling" "*.py"
require_no_tracked_regex "legacy extension files" '[.](gn|gr|gro)$'
require_no_tracked_regex "roadmap/checkpoint documents" '(^|/)(roadmap|road-map|checkpoints).*\.md$'

FORBIDDEN_TEXT='G''an|v0[.]6|codex/grboot|(^|[^[:alnum:]_])[.](gn|gr|gro)([^[:alnum:]_]|$)'
require_no_text_matches "$FORBIDDEN_TEXT"

echo "project policy: ok"
