#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REGISTRY="$ROOT/docs/17-grscall-service-registry.md"
RUNTIME_ABI="$ROOT/scripts/check_runtime_abi.sh"

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

require_runtime_fixture() {
    local service=$1
    shift
    local fixture

    for fixture in "$@"; do
        require_text "$RUNTIME_ABI" "$fixture" "$service runtime ABI fixture"
    done
}

[ -f "$REGISTRY" ] || fail "missing GrSCall registry: $REGISTRY"
[ -f "$RUNTIME_ABI" ] || fail "missing runtime ABI validator: $RUNTIME_ABI"

require_text "$REGISTRY" '# GrSCall Service Registry' "GrSCall registry title"
require_text "$REGISTRY" 'Current GrSCall entry mechanism:' "GrSCall entry mechanism heading"
require_text "$REGISTRY" 'int 30h' "GrSCall real16 entry mechanism"
require_text "$REGISTRY" 'CF = 1' "unsupported selector carry flag"
require_text "$REGISTRY" 'AX = 0001h' "unsupported selector error code"
require_text "$REGISTRY" 'scripts/check_runtime_abi.sh' "runtime ABI validation reference"

IMPLEMENTED_ROWS=$(implemented_rows)
IMPLEMENTED_COUNT=$(printf '%s\n' "$IMPLEMENTED_ROWS" | sed '/^$/d' | wc -l | tr -d ' ')
[ "$IMPLEMENTED_COUNT" = "3" ] || fail "GrSCall registry must list exactly 3 implemented services, got $IMPLEMENTED_COUNT"

require_text "$REGISTRY" '| `00h` | `00h` | `runtime/control.probe` | implemented |' "runtime/control.probe implemented row"
require_text "$REGISTRY" '| `01h` | `00h` | `console/text.write_cstr` | implemented |' "console/text.write_cstr implemented row"
require_text "$REGISTRY" '| `01h` | `01h` | `console/text.write_char` | implemented |' "console/text.write_char implemented row"

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
    "GrSCall common return paths" \
    "unsupported selector returns CF=1 AX=0001h" \
    "successful selector returns CF=0 AX=0000h"

require_absent_text "$REGISTRY" '| `00h` | `01h` | `runtime/control.version` | implemented |' "unimplemented runtime/control.version implemented row"
require_absent_text "$REGISTRY" '| `00h` | `02h` | `runtime/control.profile_id` | implemented |' "unimplemented runtime/control.profile_id implemented row"
require_absent_text "$REGISTRY" '| `01h` | `02h` | `console/text.write_crlf` | implemented |' "unimplemented console/text.write_crlf implemented row"
require_absent_text "$REGISTRY" '| `01h` | `03h` | `console/text.clear` | implemented |' "unimplemented console/text.clear implemented row"

echo "grscall registry: ok"
