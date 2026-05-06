#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEFAULT_REGISTRY="$ROOT/docs/17-grscall-service-registry.md"
DEFAULT_RUNTIME_ABI="$ROOT/scripts/check_runtime_abi.sh"
DEFAULT_RUNTIME_ABI_DOC="$ROOT/docs/10-runtime-abi-seed.md"
REGISTRY="${GRSCALL_REGISTRY_DOC:-$DEFAULT_REGISTRY}"
RUNTIME_ABI="${GRSCALL_RUNTIME_ABI_CHECK:-$DEFAULT_RUNTIME_ABI}"
RUNTIME_ABI_DOC="${GRSCALL_RUNTIME_ABI_DOC:-$DEFAULT_RUNTIME_ABI_DOC}"

fail() {
    echo "error: $1" >&2
    exit 1
}

require_text() {
    local file=$1
    local text=$2
    local name=$3

    grep -F "$text" "$file" > /dev/null || fail "missing $name: $text"
}

require_absent_text() {
    local file=$1
    local text=$2
    local name=$3

    ! grep -F "$text" "$file" > /dev/null || fail "unexpected $name: $text"
}

implemented_rows() {
    awk '
        /^## Implemented Services$/ {
            inside = 1
            next
        }
        /^## / && inside {
            inside = 0
        }
        inside && / implemented[[:space:]]*\|$/ {
            print
        }
    ' "$REGISTRY"
}

candidate_rows() {
    awk '
        /^## Candidate Next Services$/ {
            inside = 1
            next
        }
        /^## / && inside {
            inside = 0
        }
        inside {
            print
        }
    ' "$REGISTRY"
}

require_candidate_text() {
    local text=$1
    local name=$2

    if ! candidate_rows | grep -F "$text" > /dev/null; then
        fail "missing $name: $text"
    fi
}

require_runtime_fixture() {
    local service=$1
    shift
    local fixture

    for fixture in "$@"; do
        require_text "$RUNTIME_ABI" "$fixture" "$service runtime ABI fixture"
    done
}

require_absent_candidate_text() {
    local text=$1
    local name=$2

    if candidate_rows | grep -F "$text" > /dev/null; then
        fail "unexpected $name: $text"
    fi
}

if { [ -n "${GRSCALL_REGISTRY_DOC+x}" ] || [ -n "${GRSCALL_RUNTIME_ABI_CHECK+x}" ] || [ -n "${GRSCALL_RUNTIME_ABI_DOC+x}" ]; } &&
    [ "${GRSCALL_REGISTRY_SELF_TEST:-0}" != "1" ]; then
    fail "GrSCall registry overrides are only allowed with GRSCALL_REGISTRY_SELF_TEST=1"
fi

[ -f "$REGISTRY" ] || fail "missing GrSCall registry: $REGISTRY"
[ -f "$RUNTIME_ABI" ] || fail "missing runtime ABI validator: $RUNTIME_ABI"
[ -f "$RUNTIME_ABI_DOC" ] || fail "missing runtime ABI seed doc: $RUNTIME_ABI_DOC"

require_text "$REGISTRY" '# GrSCall Service Registry' "GrSCall registry title"
require_text "$REGISTRY" 'Current GrSCall entry mechanism:' "GrSCall entry mechanism heading"
require_text "$REGISTRY" 'int 30h' "GrSCall real16 entry mechanism"
require_text "$REGISTRY" 'CF = 1' "unsupported selector carry flag"
require_text "$REGISTRY" 'AX = 0001h' "unsupported selector error code"
require_text "$REGISTRY" 'scripts/check_runtime_abi.sh' "runtime ABI validation reference"

IMPLEMENTED_ROWS=$(implemented_rows)
IMPLEMENTED_COUNT=$(printf '%s\n' "$IMPLEMENTED_ROWS" | sed '/^$/d' | wc -l | tr -d ' ')
[ "$IMPLEMENTED_COUNT" = "4" ] || fail "GrSCall registry must list exactly 4 implemented services, got $IMPLEMENTED_COUNT"

require_text "$REGISTRY" '| `00h` | `00h` | `runtime/control.probe` | implemented |' "runtime/control.probe implemented row"
require_text "$REGISTRY" '| `01h` | `00h` | `console/text.write_cstr` | implemented |' "console/text.write_cstr implemented row"
require_text "$REGISTRY" '| `01h` | `01h` | `console/text.write_char` | implemented |' "console/text.write_char implemented row"
require_text "$REGISTRY" '| `01h` | `02h` | `console/text.write_crlf` | implemented |' "console/text.write_crlf implemented row"

require_absent_text "$REGISTRY" '| `02h` | `storage/block` | reserved/future |' "registry stale storage/block group assignment"
require_absent_text "$REGISTRY" '| `03h` | `process/task` | reserved/future |' "registry stale process/task group assignment"
require_absent_text "$REGISTRY" '| `04h` | `memory` | reserved/future |' "registry stale memory group assignment"
require_text "$REGISTRY" '| `02h` | `memory/seed` | reserved/future |' "memory/seed reserved group row"
require_text "$REGISTRY" '| `03h` | `boot/info` | reserved/future |' "boot/info reserved group row"
require_text "$REGISTRY" '| `04h` | `storage/block` | reserved/future |' "storage/block reserved group row"
require_text "$REGISTRY" '| `05h` | `process/task` | reserved/future |' "process/task reserved group row"

require_runtime_fixture \
    "runtime/control.probe" \
    "runtime/control probe call" \
    "runtime/control probe selector branch"

require_runtime_fixture \
    "console/text.write_cstr" \
    "console/text write selector call helper" \
    "console/text write selector branch" \
    "console/text preserves SI and falls through to success"

require_runtime_fixture \
    "console/text.write_char" \
    "console/text write-char echo call" \
    "console/text write-char selector branch" \
    "console/text write-char service body"

require_runtime_fixture \
    "console/text.write_crlf" \
    "console/text write-crlf selector call" \
    "console/text write-crlf selector branch" \
    "console/text write-crlf preserves SI and jumps to success"

require_runtime_fixture \
    "GrSCall common return paths" \
    "unsupported selector returns CF=1 AX=0001h" \
    "successful selector returns CF=0 AX=0000h"

require_absent_text "$REGISTRY" '| `00h` | `01h` | `runtime/control.version` | implemented |' "unimplemented runtime/control.version implemented row"
require_absent_text "$REGISTRY" '| `00h` | `02h` | `runtime/control.profile_id` | implemented |' "unimplemented runtime/control.profile_id implemented row"
require_absent_text "$REGISTRY" '| `01h` | `03h` | `console/text.clear` | implemented |' "unimplemented console/text.clear implemented row"
require_candidate_text '| `00h` | `01h` | `runtime/control.version` |' "runtime/control.version candidate row"
require_candidate_text '| `00h` | `02h` | `runtime/control.profile_id` |' "runtime/control.profile_id candidate row"
require_candidate_text '| `01h` | `03h` | `console/text.clear` |' "console/text.clear candidate row"
require_candidate_text '| `02h` | `00h` | `memory/seed.probe_map` |' "memory/seed.probe_map candidate row"
require_candidate_text '| `03h` | `00h` | `boot/info.drive` |' "boot/info.drive candidate row"
require_absent_candidate_text '| `01h` | `02h` | `console/text.write_crlf` |' "implemented console/text.write_crlf candidate row"

require_text "$RUNTIME_ABI_DOC" '## GrSCall Service Namespace' "runtime ABI GrSCall namespace heading"
require_text "$RUNTIME_ABI_DOC" 'docs/17-grscall-service-registry.md' "runtime ABI canonical GrSCall registry reference"
require_text "$RUNTIME_ABI_DOC" 'console/text.write_crlf' "runtime ABI write_crlf service"
require_absent_text "$RUNTIME_ABI_DOC" 'No other service IDs are implemented yet.' "runtime ABI stale no-extra-service claim"
require_absent_text "$RUNTIME_ABI_DOC" '## Initial Service Groups' "runtime ABI local GrSCall group table"
require_absent_text "$RUNTIME_ABI_DOC" '## Reserved Groups' "runtime ABI local reserved group section"
require_absent_text "$RUNTIME_ABI_DOC" '| Group | Namespace |' "runtime ABI local GrSCall namespace table"
require_absent_text "$RUNTIME_ABI_DOC" '02h  storage/block' "runtime ABI stale storage/block group assignment"
require_absent_text "$RUNTIME_ABI_DOC" '03h  process/task' "runtime ABI stale process/task group assignment"
require_absent_text "$RUNTIME_ABI_DOC" '04h  memory' "runtime ABI stale memory group assignment"
require_absent_text "$RUNTIME_ABI_DOC" '| `02h` | `storage/block` |' "runtime ABI stale storage/block table assignment"
require_absent_text "$RUNTIME_ABI_DOC" '| `03h` | `process/task` |' "runtime ABI stale process/task table assignment"
require_absent_text "$RUNTIME_ABI_DOC" '| `04h` | `memory` |' "runtime ABI stale memory table assignment"

echo "grscall registry: ok"
