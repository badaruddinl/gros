#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEFAULT_FIXTURE_ROOT="$ROOT/fixtures/generated-code"
FIXTURE_ROOT="${GENERATED_FIXTURES_ROOT:-$DEFAULT_FIXTURE_ROOT}"
PROFILE="gros.x86.bios.real16.stage2.v0"
EXPECTED_SIZE="2048"
ENTRY_ADDRESS="0000:8000"
GROUND_PROFILE_PREFIX="x86.bios.real16.generated"

fail() {
    echo "error: $1" >&2
    exit 1
}

if [ -n "${GENERATED_FIXTURES_ROOT:-}" ] && [ "${GENERATED_FIXTURES_SELF_TEST:-}" != "1" ]; then
    fail "GENERATED_FIXTURES_ROOT is only allowed with GENERATED_FIXTURES_SELF_TEST=1"
fi

validate_manifest_schema() {
    local manifest=$1
    local line
    local key
    local seen=""

    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || fail "$manifest must not contain blank lines"

        case "$line" in
            *=*)
                key=${line%%=*}
                ;;
            *)
                fail "$manifest line must use key=value: $line"
                ;;
        esac

        case "$key" in
            name|profile|source|expected_gwn|expected_gwo|expected_size|entry_address|status)
                ;;
            *)
                fail "$manifest contains unknown key: $key"
                ;;
        esac

        case " $seen " in
            *" $key "*)
                fail "$manifest contains duplicate key: $key"
                ;;
        esac
        seen="$seen $key"
    done < "$manifest"
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

require_manifest_decimal() {
    local manifest=$1
    local key=$2
    local expected=$3
    local actual

    actual=$(manifest_value "$manifest" "$key") || fail "$manifest missing key: $key"
    [[ $actual =~ ^[0-9]+$ ]] || fail "$manifest key $key must be decimal bytes, got $actual"
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

require_file_size() {
    local file=$1
    local expected=$2
    local actual

    actual=$(wc -c < "$file" | tr -d '[:space:]')
    [ "$actual" = "$expected" ] || fail "$file must be $expected bytes, got $actual"
}

fixture_ground_suffix() {
    local name=$1

    printf '%s' "$name" | tr '-' '_'
}

require_entry_origin() {
    local gwn_file=$1
    local address=$2
    local origin

    case "$address" in
        0000:8000)
            origin="8000"
            ;;
        *)
            fail "$gwn_file uses unsupported generated fixture entry address: $address"
            ;;
    esac

    grep -Eq "^[[:space:]]*origin[[:space:]]+$origin([[:space:]]*(;.*)?)?$" "$gwn_file" ||
        fail "$gwn_file origin must match entry_address $address"
}

require_source_target() {
    local source=$1
    local profile=$2

    grep -Eq "^[[:space:]]*target[[:space:]]+\"$profile\"[[:space:]]*$" "$source" ||
        fail "$source must declare target $profile"
}

require_ground_boundary() {
    local gwn_file=$1
    local fixture_name=$2
    local suffix

    suffix=$(fixture_ground_suffix "$fixture_name")
    grep -Eq "^[[:space:]]*raw[[:space:]]+x86\\.bios\\.real16\\.generated\\.$suffix[[:space:]]*\\{" "$gwn_file" ||
        fail "$gwn_file must declare raw $GROUND_PROFILE_PREFIX.$suffix"
}

check_fixture() {
    local dir=$1
    local name
    local manifest
    local manifest_profile

    name=$(basename -- "$dir")
    manifest="$dir/manifest.txt"
    [ -f "$manifest" ] || fail "fixture missing manifest: $dir"

    validate_manifest_schema "$manifest"
    require_manifest_value "$manifest" "name" "$name"
    require_manifest_value "$manifest" "profile" "$PROFILE"
    manifest_profile=$(manifest_value "$manifest" "profile") || fail "$manifest missing key: profile"
    require_manifest_value "$manifest" "status" "expected-only"
    require_manifest_file "$dir" "$manifest" "source" "source.grw"
    require_manifest_file "$dir" "$manifest" "expected_gwn" "expected.gwn"
    require_manifest_file "$dir" "$manifest" "expected_gwo" "expected.gwo"
    require_manifest_decimal "$manifest" "expected_size" "$EXPECTED_SIZE"
    require_manifest_value "$manifest" "entry_address" "$ENTRY_ADDRESS"

    require_source_target "$dir/source.grw" "$manifest_profile"
    grep -F "raw " "$dir/source.grw" > /dev/null && fail "$dir/source.grw must stay informational and must not embed raw ground code"
    grep -F "raw " "$dir/expected.gwn" > /dev/null || fail "$dir/expected.gwn must be raw .gwn source"
    require_ground_boundary "$dir/expected.gwn" "$name"
    require_entry_origin "$dir/expected.gwn" "$ENTRY_ADDRESS"
    require_file_size "$dir/expected.gwo" "$EXPECTED_SIZE"

    (
        local tmp_dir
        local built

        tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/generated-fixture.XXXXXX")
        trap 'rm -rf "$tmp_dir"' EXIT

        built="$tmp_dir/expected.gwo"
        "$ROOT/scripts/gwnraw.sh" "$dir/expected.gwn" "$built" > /dev/null
        require_file_size "$built" "$EXPECTED_SIZE"
        cmp -s "$built" "$dir/expected.gwo" || fail "$name expected.gwo must match expected.gwn build output"
    )
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
