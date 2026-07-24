#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEFAULT_FILE="$ROOT/build/gros-stage2.gwo"
FILE="$DEFAULT_FILE"
CASE_NAME=""
REQUIRE_QEMU=0
SECONDS_TO_RUN=10

usage() {
    echo "usage: qemu_stage2_interaction.sh --case <help|ver|unknown|backspace|cls> [--require-qemu] [image.gwo]" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --case)
            [ "$#" -ge 2 ] || {
                usage
                exit 2
            }
            CASE_NAME=$2
            shift 2
            ;;
        --require-qemu)
            REQUIRE_QEMU=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            usage
            exit 2
            ;;
        *)
            [ "$FILE" = "$DEFAULT_FILE" ] || {
                usage
                exit 2
            }
            FILE=$1
            shift
            ;;
    esac
done

fail() {
    echo "error: $1" >&2
    exit 1
}

require_bytes() {
    local text=$1
    local name=$2
    local expected_hex

    expected_hex=$(printf '%s' "$text" | od -An -tx1 -v | tr -d ' \n')
    case "$DEBUG_HEX" in
        *"$expected_hex"*) ;;
        *) fail "missing interaction transcript: $name" ;;
    esac
}

count_text() {
    local text=$1

    grep -aoF "$text" "$DEBUG_LOG" | wc -l | tr -d ' '
}

case "$CASE_NAME" in
    help)
        KEYS=(h e l p ret)
        ;;
    ver)
        KEYS=(v e r ret)
        ;;
    unknown)
        KEYS=(z ret)
        ;;
    backspace)
        KEYS=(x backspace h e l p ret)
        ;;
    cls)
        KEYS=(c l s ret)
        ;;
    *)
        usage
        exit 2
        ;;
esac

if [ ! -f "$FILE" ] && [ "$FILE" = "$DEFAULT_FILE" ]; then
    "$ROOT/scripts/build_stage2_image.sh"
fi

[ -f "$FILE" ] || fail "file not found: $FILE"

if ! command -v qemu-system-i386 > /dev/null 2>&1; then
    if [ "$REQUIRE_QEMU" -eq 1 ]; then
        fail "qemu-system-i386 is required for interaction validation"
    fi
    echo "qemu: skipped"
    exit 0
fi

DEBUG_LOG=$(mktemp)
MONITOR_LOG=$(mktemp)
trap 'rm -f "$DEBUG_LOG" "$MONITOR_LOG"' EXIT

set +e
{
    sleep 1
    for key in "${KEYS[@]}"; do
        printf 'sendkey %s\n' "$key"
        sleep 0.15
    done
    sleep 0.5
    printf 'quit\n'
} | timeout "$SECONDS_TO_RUN" qemu-system-i386 \
    -drive format=raw,file="$FILE" \
    -display none \
    -monitor stdio \
    -no-reboot \
    -no-shutdown \
    -debugcon "file:$DEBUG_LOG" \
    -global isa-debugcon.iobase=0xe9 \
    > "$MONITOR_LOG" 2>&1
STATUS=$?
set -e

case "$STATUS" in
    0)
        ;;
    124)
        fail "QEMU interaction timed out"
        ;;
    *)
        cat "$MONITOR_LOG" >&2
        fail "QEMU interaction exited with status $STATUS"
        ;;
esac

DEBUG_HEX=$(od -An -tx1 -v "$DEBUG_LOG" | tr -d ' \n')
require_bytes $'GrOS v0.5\r\n' 'stage-2 banner'
require_bytes 'ground> ' 'stage-2 prompt'

case "$CASE_NAME" in
    help)
        require_bytes $'ground> help\r\nhelp ver cls reboot\r\n' 'help command and response'
        ;;
    ver)
        require_bytes $'ground> ver\r\nGrOS v0.5\r\n' 'version command and response'
        ;;
    unknown)
        require_bytes $'ground> z\r\n?\r\n' 'unknown command and response'
        ;;
    backspace)
        require_bytes $'ground> x\b \bhelp\r\nhelp ver cls reboot\r\n' 'backspace-edited command and response'
        ;;
    cls)
        require_bytes $'ground> cls\r\n' 'clear-screen command echo'
        [ "$(count_text 'ground> ')" -ge 2 ] || fail "missing interaction transcript: prompt after cls"
        ;;
esac

echo "interaction case: $CASE_NAME ok"
