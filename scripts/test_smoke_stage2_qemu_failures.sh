#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/smoke_stage2_qemu.sh"
SOURCE_IMAGE="$ROOT/dist/gros-stage2.gwo"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass_count=0
BASH_BIN=${BASH:-/usr/bin/bash}

pass() {
    pass_count=$((pass_count + 1))
    echo "ok: $1"
}

fail() {
    echo "error: $1" >&2
    exit 1
}

expect_failure() {
    local name=$1
    local expected_status=$2
    local expected=$3
    shift 3
    local out="$TMP_DIR/$name.out"
    local err="$TMP_DIR/$name.err"
    local status

    set +e
    "$@" > "$out" 2> "$err"
    status=$?
    set -e

    if [ "$status" -eq 0 ]; then
        fail "$name: expected failure"
    fi
    [ "$status" -eq "$expected_status" ] ||
        fail "$name: expected status $expected_status, got $status"

    if ! grep -F "$expected" "$out" "$err" > /dev/null; then
        echo "stdout:" >&2
        cat "$out" >&2
        echo "stderr:" >&2
        cat "$err" >&2
        fail "$name: expected error containing '$expected'"
    fi

    pass "$name"
}

expect_success() {
    local name=$1
    local expected=$2
    shift 2
    local out="$TMP_DIR/$name.out"
    local err="$TMP_DIR/$name.err"

    "$@" > "$out" 2> "$err"

    if ! grep -F "$expected" "$out" "$err" > /dev/null; then
        echo "stdout:" >&2
        cat "$out" >&2
        echo "stderr:" >&2
        cat "$err" >&2
        fail "$name: expected output containing '$expected'"
    fi

    pass "$name"
}

make_path_without_qemu() {
    local path_dir=$1

    mkdir -p "$path_dir"
    {
        printf '#!%s\n' "$BASH_BIN"
        cat <<'SH'
set -euo pipefail
if [ "$#" -gt 0 ] && [ "$1" = "--" ]; then
    shift
fi
path=${1-}
case "$path" in
    */*)
        path=${path%/*}
        [ -n "$path" ] || path=/
        ;;
    *)
        path=.
        ;;
esac
printf '%s\n' "$path"
SH
    } > "$path_dir/dirname"
    chmod +x "$path_dir/dirname"
}

make_path_with_failing_qemu() {
    local path_dir=$1

    mkdir -p "$path_dir"
    {
        printf '#!%s\n' "$BASH_BIN"
        cat <<'SH'
set -euo pipefail
shift
"$@"
SH
    } > "$path_dir/timeout"
    chmod +x "$path_dir/timeout"

    {
        printf '#!%s\n' "$BASH_BIN"
        cat <<'SH'
set -euo pipefail
saw_drive=0
for arg in "$@"; do
    case "$arg" in
        format=raw,file=*)
            saw_drive=1
            ;;
    esac
done
[ "$saw_drive" -eq 1 ] || {
    echo "fake qemu missing raw drive argument" >&2
    exit 43
}
echo "fake qemu failure" >&2
exit 7
SH
    } > "$path_dir/qemu-system-i386"
    chmod +x "$path_dir/qemu-system-i386"
}

make_path_with_timeout_qemu() {
    local path_dir=$1

    mkdir -p "$path_dir"
    {
        printf '#!%s\n' "$BASH_BIN"
        cat <<'SH'
set -euo pipefail
exit 124
SH
    } > "$path_dir/timeout"
    chmod +x "$path_dir/timeout"

    {
        printf '#!%s\n' "$BASH_BIN"
        cat <<'SH'
set -euo pipefail
exit 0
SH
    } > "$path_dir/qemu-system-i386"
    chmod +x "$path_dir/qemu-system-i386"
}

[ -f "$SOURCE_IMAGE" ] || fail "missing source stage-2 image: $SOURCE_IMAGE"
INVALID_IMAGE="$TMP_DIR/invalid.gwo"
printf 'not a boot image\n' > "$INVALID_IMAGE"

bash -n "$VALIDATOR"
pass "validator syntax"

expect_failure "unknown-option" 2 "usage:" "$BASH_BIN" "$VALIDATOR" --unknown "$SOURCE_IMAGE"
expect_failure "too-many-images" 2 "usage:" "$BASH_BIN" "$VALIDATOR" "$SOURCE_IMAGE" "$SOURCE_IMAGE"
expect_failure "missing-image" 1 "file not found:" "$BASH_BIN" "$VALIDATOR" "$TMP_DIR/missing.gwo"

NO_QEMU_PATH="$TMP_DIR/no-qemu-bin"
make_path_without_qemu "$NO_QEMU_PATH"
expect_failure "missing-qemu-required" 1 "qemu-system-i386 is required for this smoke test" \
    env PATH="$NO_QEMU_PATH" "$BASH_BIN" "$VALIDATOR" --require-qemu "$SOURCE_IMAGE"
expect_success "missing-qemu-optional" "qemu: skipped" \
    env PATH="$NO_QEMU_PATH" "$BASH_BIN" "$VALIDATOR" "$SOURCE_IMAGE"

FAILING_QEMU_PATH="$TMP_DIR/failing-qemu-bin"
make_path_with_failing_qemu "$FAILING_QEMU_PATH"
expect_failure "qemu-failure-status" 1 "error: qemu exited with status 7" \
    env PATH="$FAILING_QEMU_PATH:$PATH" "$BASH_BIN" "$VALIDATOR" --require-qemu "$INVALID_IMAGE"

TIMEOUT_QEMU_PATH="$TMP_DIR/timeout-qemu-bin"
make_path_with_timeout_qemu "$TIMEOUT_QEMU_PATH"
expect_success "qemu-timeout-accepted" "ok: qemu smoke start" \
    env PATH="$TIMEOUT_QEMU_PATH:$PATH" "$BASH_BIN" "$VALIDATOR" --require-qemu "$SOURCE_IMAGE"

echo "passed: $pass_count"
