#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: grraw.sh <source.gr> <output.gro>" >&2
    exit 2
fi

SRC=$1
OUT=$2
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

trim() {
    local value=$1
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s' "$value"
}

emit_byte() {
    local token=$1
    local line_no=$2
    if [[ ! $token =~ ^[0-9A-Fa-f]{2}$ ]]; then
        echo "line $line_no: invalid byte: $token" >&2
        exit 1
    fi
    printf '%b' "\\x$token"
}

emit_ascii() {
    local payload=$1
    local line_no=$2
    if [[ ! $payload =~ ^\".*\"$ ]]; then
        echo "line $line_no: ascii expects a quoted string" >&2
        exit 1
    fi
    payload=${payload#\"}
    payload=${payload%\"}
    printf '%b' "$payload"
}

pad_to() {
    local size=$1
    local byte=$2
    local line_no=$3
    local current
    current=$(wc -c < "$TMP" | tr -d ' ')
    if [ "$current" -gt "$size" ]; then
        echo "line $line_no: output is $current bytes, cannot pad back to $size" >&2
        exit 1
    fi
    while [ "$current" -lt "$size" ]; do
        emit_byte "$byte" "$line_no" >> "$TMP"
        current=$((current + 1))
    done
}

line_no=0
while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    line_no=$((line_no + 1))
    line=$(trim "${raw_line%%;*}")
    [ -z "$line" ] && continue
    [[ $line == raw\ * ]] && continue
    [ "$line" = "}" ] && continue

    read -r directive rest <<< "$line"
    rest=$(trim "${rest:-}")

    case "$directive" in
        bytes)
            for token in $rest; do
                emit_byte "$token" "$line_no" >> "$TMP"
            done
            ;;
        byte)
            emit_byte "$rest" "$line_no" >> "$TMP"
            ;;
        ascii)
            emit_ascii "$rest" "$line_no" >> "$TMP"
            ;;
        pad_to)
            read -r size keyword byte extra <<< "$rest"
            if [ "${keyword:-}" != "with" ] || [ -z "${byte:-}" ] || [ -n "${extra:-}" ]; then
                echo "line $line_no: expected pad_to <size> with <byte>" >&2
                exit 1
            fi
            pad_to "$size" "$byte" "$line_no"
            ;;
        signature)
            for token in $rest; do
                emit_byte "$token" "$line_no" >> "$TMP"
            done
            ;;
        *)
            echo "line $line_no: unknown directive: $directive" >&2
            exit 1
            ;;
    esac
done < "$SRC"

mkdir -p "$(dirname "$OUT")"
mv "$TMP" "$OUT"
trap - EXIT
