#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FIXTURE_ROOT="$ROOT/fixtures/gwo-header"
SEED_MAGIC="47524f00"
SEED_HEADER_SIZE="32"
SEED_HEADER_VERSION="0"
SEED_PROFILE_ID="0"
SEED_FLAGS="0"
SEED_CHECKSUM="0"
ACCEPT_COUNT=0
REJECT_COUNT=0
REQUIRED_FIXTURES="
bad-header-size
bad-magic
bad-version
entry-out-of-range
nonzero-flags
nonzero-reserved
nonzero-checksum
payload-size-mismatch
truncated-header
unknown-profile
zero-payload-size
valid-entry-last-byte
valid-minimal
"

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
    local actual

    actual=$(manifest_value "$manifest" "$key") || fail "$manifest missing key: $key"
    [ -f "$dir/$actual" ] || fail "fixture missing file declared by $key: $dir/$actual"
}

require_manifest_schema() {
    local manifest=$1
    local line
    local key
    local count

    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || fail "$manifest must not contain blank lines"
        case "$line" in
            *=*)
                ;;
            *)
                fail "$manifest line must use key=value: $line"
                ;;
        esac

        key=${line%%=*}
        [ -n "$key" ] || fail "$manifest contains an empty key"

        case "$key" in
            name|status|candidate_hex|expected_result|expected_error|total_size|magic|header_size|header_version|profile_id|flags|entry_offset|payload_size|payload_checksum|reserved|payload)
                ;;
            *)
                fail "$manifest contains unknown key: $key"
                ;;
        esac

        count=$(awk -F= -v key="$key" '$1 == key { count++ } END { print count + 0 }' "$manifest")
        [ "$count" -eq 1 ] || fail "$manifest contains duplicate key: $key"
    done < "$manifest"
}

hex_stream() {
    local file=$1
    local hex

    hex=$(tr -d '[:space:]' < "$file" | tr '[:upper:]' '[:lower:]')
    [[ $hex =~ ^[0-9a-f]*$ ]] || fail "$file must contain only hex bytes and whitespace"
    [ $(( ${#hex} % 2 )) -eq 0 ] || fail "$file must contain a whole number of bytes"
    printf '%s' "$hex"
}

hex_slice() {
    local hex=$1
    local offset=$2
    local size=$3

    printf '%s' "${hex:$((offset * 2)):$((size * 2))}"
}

le16() {
    local bytes=$1

    printf '%d' "$((16#${bytes:2:2}${bytes:0:2}))"
}

le32() {
    local bytes=$1

    printf '%d' "$((16#${bytes:6:2}${bytes:4:2}${bytes:2:2}${bytes:0:2}))"
}

is_zero_hex() {
    local bytes=$1

    [[ $bytes =~ ^0+$ ]]
}

require_decoded_manifest() {
    local manifest=$1
    local hex=$2
    local byte_len=$(( ${#hex} / 2 ))

    require_manifest_value "$manifest" "total_size" "$byte_len"

    if [ "$byte_len" -ge 4 ]; then
        require_manifest_value "$manifest" "magic" "$(hex_slice "$hex" 0 4)"
    fi

    if [ "$byte_len" -ge 6 ]; then
        require_manifest_value "$manifest" "header_size" "$(le16 "$(hex_slice "$hex" 4 2)")"
    fi

    if [ "$byte_len" -ge 8 ]; then
        require_manifest_value "$manifest" "header_version" "$(le16 "$(hex_slice "$hex" 6 2)")"
    fi

    if [ "$byte_len" -ge 12 ]; then
        require_manifest_value "$manifest" "profile_id" "$(le32 "$(hex_slice "$hex" 8 4)")"
    fi

    if [ "$byte_len" -ge 14 ]; then
        require_manifest_value "$manifest" "flags" "$(le16 "$(hex_slice "$hex" 12 2)")"
    fi

    if [ "$byte_len" -ge 16 ]; then
        require_manifest_value "$manifest" "entry_offset" "$(le16 "$(hex_slice "$hex" 14 2)")"
    fi

    if [ "$byte_len" -ge 20 ]; then
        require_manifest_value "$manifest" "payload_size" "$(le32 "$(hex_slice "$hex" 16 4)")"
    fi

    if [ "$byte_len" -ge 24 ]; then
        require_manifest_value "$manifest" "payload_checksum" "$(le32 "$(hex_slice "$hex" 20 4)")"
    fi

    if [ "$byte_len" -ge 32 ]; then
        require_manifest_value "$manifest" "reserved" "$(hex_slice "$hex" 24 8)"
        require_manifest_value "$manifest" "payload" "$(hex_slice "$hex" 32 $((byte_len - 32)))"
    fi
}

validate_header_hex() {
    local hex=$1
    local byte_len=$(( ${#hex} / 2 ))
    local magic
    local header_size
    local header_version
    local profile_id
    local flags
    local entry_offset
    local payload_size
    local payload_checksum
    local reserved
    local actual_payload_size

    [ "$byte_len" -ge 32 ] || {
        echo "truncated_header"
        return
    }

    magic=$(hex_slice "$hex" 0 4)
    [ "$magic" = "$SEED_MAGIC" ] || {
        echo "magic"
        return
    }

    header_size=$(le16 "$(hex_slice "$hex" 4 2)")
    [ "$header_size" = "$SEED_HEADER_SIZE" ] || {
        echo "header_size"
        return
    }

    header_version=$(le16 "$(hex_slice "$hex" 6 2)")
    [ "$header_version" = "$SEED_HEADER_VERSION" ] || {
        echo "header_version"
        return
    }

    profile_id=$(le32 "$(hex_slice "$hex" 8 4)")
    [ "$profile_id" = "$SEED_PROFILE_ID" ] || {
        echo "profile_id"
        return
    }

    flags=$(le16 "$(hex_slice "$hex" 12 2)")
    [ "$flags" = "$SEED_FLAGS" ] || {
        echo "flags"
        return
    }

    entry_offset=$(le16 "$(hex_slice "$hex" 14 2)")
    payload_size=$(le32 "$(hex_slice "$hex" 16 4)")
    payload_checksum=$(le32 "$(hex_slice "$hex" 20 4)")
    [ "$payload_checksum" = "$SEED_CHECKSUM" ] || {
        echo "payload_checksum"
        return
    }

    reserved=$(hex_slice "$hex" 24 8)
    is_zero_hex "$reserved" || {
        echo "reserved"
        return
    }

    actual_payload_size=$(( byte_len - header_size ))
    [ "$actual_payload_size" -eq "$payload_size" ] || {
        echo "payload_size"
        return
    }

    [ "$payload_size" -gt 0 ] || {
        echo "payload_size"
        return
    }

    [ "$entry_offset" -lt "$payload_size" ] || {
        echo "entry_offset"
        return
    }

    echo "ok"
}

check_raw_artifact_separation() {
    local artifact=$1
    local magic

    [ -f "$artifact" ] || return
    magic=$(od -An -tx1 -N4 "$artifact" | tr -d '[:space:]')
    [ "$magic" != "$SEED_MAGIC" ] || fail "$artifact must remain a raw-profile artifact without GWO header magic"
}

check_fixture() {
    local dir=$1
    local name
    local manifest
    local candidate_hex_file
    local expected_result
    local expected_error
    local hex
    local actual

    name=$(basename -- "$dir")
    manifest="$dir/manifest.txt"
    [ -f "$manifest" ] || fail "fixture missing manifest: $dir"
    require_manifest_schema "$manifest"

    require_manifest_value "$manifest" "name" "$name"
    require_manifest_value "$manifest" "status" "header-candidate"
    require_manifest_file "$dir" "$manifest" "candidate_hex"

    candidate_hex_file=$(manifest_value "$manifest" "candidate_hex") || fail "$manifest missing key: candidate_hex"
    [ "$candidate_hex_file" = "candidate.gwo.hex" ] || fail "$manifest candidate_hex must be candidate.gwo.hex"
    expected_result=$(manifest_value "$manifest" "expected_result") || fail "$manifest missing key: expected_result"
    expected_error=$(manifest_value "$manifest" "expected_error") || fail "$manifest missing key: expected_error"

    case "$expected_result" in
        accept|reject)
            ;;
        *)
            fail "$manifest expected_result must be accept or reject"
            ;;
    esac

    hex=$(hex_stream "$dir/$candidate_hex_file")
    require_decoded_manifest "$manifest" "$hex"
    actual=$(validate_header_hex "$hex")

    if [ "$expected_result" = "accept" ]; then
        [ "$expected_error" = "none" ] || fail "$manifest accepted fixtures must use expected_error=none"
        [ "$actual" = "ok" ] || fail "$name expected accept, got $actual"
        ACCEPT_COUNT=$((ACCEPT_COUNT + 1))
    else
        [ "$expected_error" != "none" ] || fail "$manifest rejected fixtures must declare expected_error"
        [ "$actual" = "$expected_error" ] || fail "$name expected reject $expected_error, got $actual"
        REJECT_COUNT=$((REJECT_COUNT + 1))
    fi

    echo "gwo header fixture: $name $expected_result ok"
}

check_raw_artifact_separation "$ROOT/dist/gros-v0.5.gwo"
check_raw_artifact_separation "$ROOT/dist/gros-stage2.gwo"

if [ ! -d "$FIXTURE_ROOT" ]; then
    fail "missing GWO header fixture root: $FIXTURE_ROOT"
fi

for required_fixture in $REQUIRED_FIXTURES; do
    [ -d "$FIXTURE_ROOT/$required_fixture" ] || fail "missing required GWO header fixture: $required_fixture"
done

FOUND=0
for dir in "$FIXTURE_ROOT"/*; do
    [ -d "$dir" ] || continue
    FOUND=1
    check_fixture "$dir"
done

[ "$FOUND" -eq 1 ] || fail "GWO header fixture root is empty: $FIXTURE_ROOT"
[ "$ACCEPT_COUNT" -gt 0 ] || fail "GWO header fixtures must include at least one accepted candidate"
[ "$REJECT_COUNT" -gt 0 ] || fail "GWO header fixtures must include at least one rejected candidate"

echo "gwo header fixtures: ok"
