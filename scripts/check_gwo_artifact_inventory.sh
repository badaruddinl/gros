#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
HEADER_MAGIC="47524f00"

REQUIRED_GWO_ARTIFACTS="
dist/gros-v0.5.gwo
dist/gros-stage2.gwo
fixtures/generated-code/minimal-main-void/expected.gwo
"

fail() {
    echo "error: $1" >&2
    exit 1
}

is_required_gwo_artifact() {
    local candidate=$1
    local artifact

    for artifact in $REQUIRED_GWO_ARTIFACTS; do
        [ "$candidate" = "$artifact" ] && return 0
    done

    return 1
}

tracked_magic() {
    local path=$1

    od -An -tx1 -N4 "$ROOT/$path" | tr -d '[:space:]'
}

check_dist_raw_artifact() {
    local path=$1
    local magic

    [ -f "$ROOT/$path" ] || fail "missing tracked dist GWO artifact: $path"
    [ -s "$ROOT/$path" ] || fail "empty tracked dist GWO artifact: $path"

    magic=$(tracked_magic "$path")
    [ "$magic" != "$HEADER_MAGIC" ] || fail "$path must remain a raw-profile artifact without GWO header magic"
}

check_generated_expected_artifact() {
    local path=$1
    local dir

    [ -f "$ROOT/$path" ] || fail "missing expected-only GWO fixture artifact: $path"
    [ -s "$ROOT/$path" ] || fail "empty expected-only GWO fixture artifact: $path"

    dir=$(dirname -- "$path")
    grep -F 'status=expected-only' "$ROOT/$dir/manifest.txt" > /dev/null || fail "$path must belong to an expected-only generated-code fixture"
}

for artifact in $REQUIRED_GWO_ARTIFACTS; do
    git -C "$ROOT" ls-files --error-unmatch "$artifact" > /dev/null 2>&1 || fail "required GWO artifact is not tracked: $artifact"
done

while IFS= read -r path; do
    [ -n "$path" ] || continue

    is_required_gwo_artifact "$path" || fail "unexpected tracked GWO artifact: $path"

    case "$path" in
        dist/*.gwo)
            check_dist_raw_artifact "$path"
            ;;
        fixtures/generated-code/*/expected.gwo)
            check_generated_expected_artifact "$path"
            ;;
        fixtures/gwo-header/*.gwo|fixtures/gwo-header/*/*.gwo)
            fail "headered GWO fixtures must stay reviewable manifest/hex files, not tracked binary GWO artifacts: $path"
            ;;
        *)
            fail "unclassified tracked GWO artifact: $path"
            ;;
    esac
done < <(git -C "$ROOT" ls-files '*.gwo' | sort)

echo "gwo artifact inventory: ok"
