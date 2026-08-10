#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "error: $1" >&2
    exit 2
}

[ "$#" -ge 2 ] || fail "usage: $0 <lane-name> <command> [args ...]"

LANE=$1
shift

START=$(date +%s)
set +e
"$@"
STATUS=$?
set -e
END=$(date +%s)
DURATION=$((END - START))

if [ "$STATUS" -eq 0 ]; then
    echo "validation lane: $LANE: ok (${DURATION}s)"
else
    echo "validation lane: $LANE: failed (status=$STATUS, ${DURATION}s)" >&2
fi

exit "$STATUS"
