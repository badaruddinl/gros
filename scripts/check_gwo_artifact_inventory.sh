#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SELF_TEST=${GWO_ARTIFACT_INVENTORY_SELF_TEST:-0}
INVENTORY_ROOT="$ROOT"
INVENTORY_LIST=""
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

case "$SELF_TEST" in
    0|1)
        ;;
    *)
        fail "GWO_ARTIFACT_INVENTORY_SELF_TEST must be 0 or 1"
        ;;
esac

if [ "${GWO_ARTIFACT_INVENTORY_ROOT+x}" ] || [ "${GWO_ARTIFACT_INVENTORY_LIST+x}" ]; then
    [ "$SELF_TEST" = "1" ] || fail "GWO artifact inventory overrides are only allowed with GWO_ARTIFACT_INVENTORY_SELF_TEST=1"
    INVENTORY_ROOT=${GWO_ARTIFACT_INVENTORY_ROOT:-$ROOT}
    INVENTORY_LIST=${GWO_ARTIFACT_INVENTORY_LIST:-}
    [ -n "$INVENTORY_LIST" ] || fail "GWO_ARTIFACT_INVENTORY_LIST is required in self-test mode"
    [ -f "$INVENTORY_LIST" ] || fail "missing self-test artifact inventory list: $INVENTORY_LIST"
fi

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

    od -An -tx1 -N4 "$INVENTORY_ROOT/$path" | tr -d '[:space:]'
}

is_tracked_gwo_artifact() {
    local path=$1

    if [ "$SELF_TEST" = "1" ]; then
        grep -Fx "$path" "$INVENTORY_LIST" > /dev/null
    else
        git -C "$ROOT" ls-files --error-unmatch "$path" > /dev/null 2>&1
    fi
}

list_tracked_gwo_artifacts() {
    if [ "$SELF_TEST" = "1" ]; then
        grep '[.]gwo$' "$INVENTORY_LIST" | sort
    else
        git -C "$ROOT" ls-files '*.gwo' | sort
    fi
}

check_dist_raw_artifact() {
    local path=$1
    local magic

    [ -f "$INVENTORY_ROOT/$path" ] || fail "missing tracked dist GWO artifact: $path"
    [ -s "$INVENTORY_ROOT/$path" ] || fail "empty tracked dist GWO artifact: $path"

    magic=$(tracked_magic "$path")
    [ "$magic" != "$HEADER_MAGIC" ] || fail "$path must remain a raw-profile artifact without GWO header magic"
}

check_generated_expected_artifact() {
    local path=$1
    local dir

    [ -f "$INVENTORY_ROOT/$path" ] || fail "missing expected-only GWO fixture artifact: $path"
    [ -s "$INVENTORY_ROOT/$path" ] || fail "empty expected-only GWO fixture artifact: $path"

    dir=$(dirname -- "$path")
    grep -F 'status=expected-only' "$INVENTORY_ROOT/$dir/manifest.txt" > /dev/null || fail "$path must belong to an expected-only generated-code fixture"
}

for artifact in $REQUIRED_GWO_ARTIFACTS; do
    is_tracked_gwo_artifact "$artifact" || fail "required GWO artifact is not tracked: $artifact"
done

while IFS= read -r path; do
    [ -n "$path" ] || continue

    case "$path" in
        fixtures/gwo-header/*.gwo|fixtures/gwo-header/*/*.gwo)
            fail "headered GWO fixtures must stay reviewable manifest/hex files, not tracked binary GWO artifacts: $path"
            ;;
    esac

    is_required_gwo_artifact "$path" || fail "unexpected tracked GWO artifact: $path"

    case "$path" in
        dist/*.gwo)
            check_dist_raw_artifact "$path"
            ;;
        fixtures/generated-code/*/expected.gwo)
            check_generated_expected_artifact "$path"
            ;;
        *)
            fail "unclassified tracked GWO artifact: $path"
            ;;
    esac
done < <(list_tracked_gwo_artifacts)

echo "gwo artifact inventory: ok"
