#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RUNNER="$ROOT/scripts/qemu_stage2_interaction.sh"
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

expect_success() {
    local name=$1
    local expected=$2
    shift 2
    local out="$TMP_DIR/$name.out"
    local err="$TMP_DIR/$name.err"

    "$@" > "$out" 2> "$err"
    grep -F "$expected" "$out" "$err" > /dev/null || {
        cat "$out" >&2
        cat "$err" >&2
        fail "$name: expected output containing '$expected'"
    }
    pass "$name"
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

    [ "$status" -ne 0 ] || fail "$name: expected failure"
    [ "$status" -eq "$expected_status" ] || fail "$name: expected status $expected_status, got $status"
    grep -F "$expected" "$out" "$err" > /dev/null || {
        cat "$out" >&2
        cat "$err" >&2
        fail "$name: expected error containing '$expected'"
    }
    pass "$name"
}

make_fake_qemu() {
    local path_dir=$1

    mkdir -p "$path_dir"
    {
        printf '#!%s\n' "$BASH_BIN"
        cat <<'SH'
set -euo pipefail
debug_log=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -debugcon)
            debug_log=${2#file:}
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
[ -n "$debug_log" ] || {
    echo "fake qemu missing debug console path" >&2
    exit 43
}
cat > /dev/null
case ${FAKE_QEMU_MODE:-transcript} in
    transcript)
        cp "$FAKE_QEMU_TRANSCRIPT" "$debug_log"
        ;;
    failure)
        echo "fake qemu failure" >&2
        exit 7
        ;;
    *)
        echo "fake qemu unknown mode" >&2
        exit 44
        ;;
esac
SH
    } > "$path_dir/qemu-system-i386"
    chmod +x "$path_dir/qemu-system-i386"
}

write_transcript() {
    local file=$1
    local case_name=$2

    case "$case_name" in
        help) printf 'GrOS v0.5\r\nground> help\r\nhelp ver cls reboot\r\nground> ' > "$file" ;;
        ver) printf 'GrOS v0.5\r\nground> ver\r\nGrOS v0.5\r\nground> ' > "$file" ;;
        unknown) printf 'GrOS v0.5\r\nground> z\r\n?\r\nground> ' > "$file" ;;
        backspace) printf 'GrOS v0.5\r\nground> x\b \bhelp\r\nhelp ver cls reboot\r\nground> ' > "$file" ;;
        cls) printf 'GrOS v0.5\r\nground> cls\r\nground> ' > "$file" ;;
        incomplete) printf 'GrOS v0.5\r\nground> help\r\nground> ' > "$file" ;;
        *) fail "unknown transcript case: $case_name" ;;
    esac
}

[ -f "$SOURCE_IMAGE" ] || fail "missing source stage-2 image: $SOURCE_IMAGE"
bash -n "$RUNNER"
pass "runner syntax"

expect_failure "missing-case" 2 "usage:" "$BASH_BIN" "$RUNNER" "$SOURCE_IMAGE"
expect_failure "unknown-case" 2 "usage:" "$BASH_BIN" "$RUNNER" --case nope "$SOURCE_IMAGE"
expect_failure "missing-image" 1 "file not found:" "$BASH_BIN" "$RUNNER" --case help "$TMP_DIR/missing.gwo"

NO_QEMU_PATH="$TMP_DIR/no-qemu-bin"
mkdir -p "$NO_QEMU_PATH"
expect_failure "missing-qemu-required" 1 "qemu-system-i386 is required for interaction validation" \
    env PATH="$NO_QEMU_PATH" "$BASH_BIN" "$RUNNER" --case help --require-qemu "$SOURCE_IMAGE"
expect_success "missing-qemu-optional" "qemu: skipped" \
    env PATH="$NO_QEMU_PATH" "$BASH_BIN" "$RUNNER" --case help "$SOURCE_IMAGE"

FAKE_QEMU_PATH="$TMP_DIR/fake-qemu-bin"
make_fake_qemu "$FAKE_QEMU_PATH"
for case_name in help ver unknown backspace cls; do
    transcript="$TMP_DIR/$case_name.transcript"
    write_transcript "$transcript" "$case_name"
    expect_success "transcript-$case_name" "interaction case: $case_name ok" \
        env PATH="$FAKE_QEMU_PATH:$PATH" FAKE_QEMU_TRANSCRIPT="$transcript" \
        "$BASH_BIN" "$RUNNER" --case "$case_name" --require-qemu "$SOURCE_IMAGE"
done

INCOMPLETE_TRANSCRIPT="$TMP_DIR/incomplete.transcript"
write_transcript "$INCOMPLETE_TRANSCRIPT" incomplete
expect_failure "missing-help-response" 1 "missing interaction transcript: help command and response" \
    env PATH="$FAKE_QEMU_PATH:$PATH" FAKE_QEMU_TRANSCRIPT="$INCOMPLETE_TRANSCRIPT" \
    "$BASH_BIN" "$RUNNER" --case help --require-qemu "$SOURCE_IMAGE"
expect_failure "qemu-failure-status" 1 "QEMU interaction exited with status 7" \
    env PATH="$FAKE_QEMU_PATH:$PATH" FAKE_QEMU_MODE=failure \
    "$BASH_BIN" "$RUNNER" --case help --require-qemu "$SOURCE_IMAGE"

echo "passed: $pass_count"
