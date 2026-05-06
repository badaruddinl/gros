#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FIXTURE_ROOT="$ROOT/fixtures/generated-code"
PROFILE="gros.x86.bios.real16.stage2.v0"

fail() {
    echo "error: $1" >&2
    exit 1
}

manifest_value() {
    local manifest=$1
    local key=$2

    awk -F= -v key="$key" '
        $1 == key {
            value = substr($0, length(key) + 2)
            print value
            found = 1
        }
        END { if (!found) exit 1 }
    ' "$manifest"
}

require_manifest_value() {
    local manifest=$1
    local key=$2
    local expected=$3
    local actual

    actual=$(manifest_value "$manifest" "$key") || fail "$manifest missing key: $key"
    [ "$actual" = "$expected" ] || fail "$manifest key $key must be $expected, got $actual"
}

require_manifest_file() {
    local dir=$1
    local manifest=$2
    local key=$3
    local expected_name=$4
    local actual

    actual=$(manifest_value "$manifest" "$key") || fail "$manifest missing key: $key"
    [ "$actual" = "$expected_name" ] || fail "$manifest key $key must be $expected_name, got $actual"
    [ -f "$dir/$actual" ] || fail "fixture missing file declared by $key: $dir/$actual"
}

check_fixture() {
    local dir=$1
    local name
    local manifest
    local tmp_dir
    local built

    name=$(basename -- "$dir")
    manifest="$dir/manifest.txt"
    [ -f "$manifest" ] || fail "fixture missing manifest: $dir"

    require_manifest_value "$manifest" "name" "$name"
    require_manifest_value "$manifest" "profile" "$PROFILE"
    require_manifest_value "$manifest" "status" "expected-only"
    require_manifest_file "$dir" "$manifest" "source" "source.gn"
    require_manifest_file "$dir" "$manifest" "expected_gr" "expected.gr"
    require_manifest_file "$dir" "$manifest" "expected_gro" "expected.gro"

    grep -F "target \"$PROFILE\"" "$dir/source.gn" > /dev/null || fail "$dir/source.gn must declare target $PROFILE"
    grep -F "raw " "$dir/source.gn" > /dev/null && fail "$dir/source.gn must stay informational and must not embed raw ground code"
    grep -F "raw " "$dir/expected.gr" > /dev/null || fail "$dir/expected.gr must be raw .gr source"

    tmp_dir=$(mktemp -d "$ROOT/build/generated-fixture.XXXXXX")
    built="$tmp_dir/expected.gro"
    trap 'rm -rf "$tmp_dir"' RETURN

    "$ROOT/scripts/grraw.sh" "$dir/expected.gr" "$built" > /dev/null
    cmp -s "$built" "$dir/expected.gro" || fail "$name expected.gro must match expected.gr build output"

    rm -rf "$tmp_dir"
    trap - RETURN
    echo "generated fixture: $name ok"
}

if [ ! -d "$FIXTURE_ROOT" ]; then
    echo "generated fixtures: none"
    exit 0
fi

FOUND=0
for dir in "$FIXTURE_ROOT"/*; do
    [ -d "$dir" ] || continue
    FOUND=1
    check_fixture "$dir"
done

if [ "$FOUND" -eq 0 ]; then
    echo "generated fixtures: none"
else
    echo "generated fixtures: ok"
fi
