#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEFAULT_FILE="$ROOT/build/gros-stage2.gwo"
FILE="$DEFAULT_FILE"
REQUIRE_QEMU=0
SECONDS_TO_RUN=3
POSITIONAL_SEEN=0

usage() {
    echo "usage: smoke_stage2_qemu.sh [--require-qemu] [image.gwo]" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
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
            if [ "$POSITIONAL_SEEN" -eq 1 ]; then
                usage
                exit 2
            fi
            FILE=$1
            POSITIONAL_SEEN=1
            shift
            ;;
    esac
done

fail() {
    echo "error: $1" >&2
    exit 1
}

if [ ! -f "$FILE" ] && [ "$FILE" = "$DEFAULT_FILE" ]; then
    "$ROOT/scripts/build_stage2_image.sh"
fi

[ -f "$FILE" ] || fail "file not found: $FILE"

if ! command -v qemu-system-i386 > /dev/null 2>&1; then
    if [ "$REQUIRE_QEMU" -eq 1 ]; then
        fail "qemu-system-i386 is required for this smoke test"
    fi
    echo "qemu: skipped"
    exit 0
fi

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

set +e
timeout "$SECONDS_TO_RUN" qemu-system-i386 \
    -drive format=raw,file="$FILE" \
    -display none \
    -no-reboot \
    -no-shutdown \
    > "$LOG" 2>&1
STATUS=$?
set -e

case "$STATUS" in
    0|124)
        echo "ok: qemu smoke start"
        ;;
    *)
        cat "$LOG" >&2
        fail "qemu exited with status $STATUS"
        ;;
esac
