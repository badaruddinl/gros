#!/usr/bin/env bash
set -euo pipefail

DEFAULT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ROOT=${STATUS_CONSISTENCY_ROOT:-$DEFAULT_ROOT}

fail() { echo "error: $1" >&2; exit 1; }

if [ -n "${STATUS_CONSISTENCY_ROOT:-}" ] && [ "${STATUS_CONSISTENCY_SELF_TEST:-}" != "1" ]; then
    fail "STATUS_CONSISTENCY_ROOT is only allowed with STATUS_CONSISTENCY_SELF_TEST=1"
fi

require_text() {
    local file=$1
    local text=$2
    grep -F "$text" "$ROOT/$file" > /dev/null || fail "$file is missing current status text: $text"
}

forbid_text() {
    local file=$1
    local text=$2
    if grep -F "$text" "$ROOT/$file" > /dev/null; then
        fail "$file contains stale status text: $text"
    fi
}

require_text docs/00-naming.md 'minimal documented subset is compiled'
require_text docs/00-naming.md 'fixed stage-2 headered payload is implemented'
require_text docs/08-project-overview.md 'minimal documented subset is compiled'
require_text docs/11-gwo-payload-header.md 'fixed v1 header is implemented'
require_text docs/13-abi-stability-gate.md 'fixed v1 stage-2 header and loader implemented'
require_text docs/14-real16-memory-model.md 'minimal-main subset is compiled'
require_text docs/18-profile-registry.md 'profile_id 0 is assigned'
require_text docs/18-profile-registry.md 'profile query service is implemented'
require_text docs/22-grabi-contract-status.md 'fixed stage-2 reservation'
require_text docs/24-implementation-readiness-status.md 'fixed stage-2 loader implemented'
require_text docs/50-self-hosting-alpha-operations.md 'The compiler boundary is release-closed'
require_text docs/50-self-hosting-alpha-operations.md 'Each ATA branch emits a distinct'
require_text docs/50-self-hosting-alpha-evidence.md 'ATA fault coverage'

forbid_text docs/00-naming.md 'Grown .grw is specified but not compiled yet.'
forbid_text docs/08-project-overview.md 'compiler, interpreter, parser, and build integration are not implemented yet.'
forbid_text docs/14-real16-memory-model.md 'This example is not compiled by the current repository.'
forbid_text docs/18-profile-registry.md 'header-aware loader is not implemented'
forbid_text docs/18-profile-registry.md 'profile query service is not implemented'
forbid_text docs/13-abi-stability-gate.md 'header seed reserved, loader not implemented'
forbid_text docs/24-implementation-readiness-status.md '| header-aware `.gwo` executable loader | closed |'
forbid_text docs/50-self-hosting-alpha-operations.md 'Until P0 compiler-boundary hardening is complete'
forbid_text docs/50-self-hosting-alpha-operations.md 'Validation-only device-`ERR` and ATA poll-timeout injection remain open'
forbid_text docs/50-self-hosting-alpha-evidence.md 'branch: feature/self-hosting-alpha-hardening'
forbid_text docs/50-self-hosting-alpha-evidence.md 'commit: HEAD'

echo "status consistency: ok"
