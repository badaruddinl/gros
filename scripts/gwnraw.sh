#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: gwnraw.sh <source.gwn> <output.gwo>" >&2
    exit 2
fi

SRC=$1
OUT=$2
TMP=$(mktemp)
SRC_COPY=$(mktemp)
trap 'rm -f "$TMP" "$SRC_COPY"' EXIT

cp "$SRC" "$SRC_COPY"

declare -A LABELS=()
ORIGIN=0
ORIGIN_SET=0
OFFSET=0

trim() {
    local value=$1
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s' "$value"
}

strip_comment() {
    local line=$1
    local out=
    local char
    local in_string=0
    local escaped=0
    local i
    for ((i = 0; i < ${#line}; i++)); do
        char=${line:i:1}
        if [ "$escaped" -eq 1 ]; then
            out+=$char
            escaped=0
            continue
        fi
        if [ "$char" = "\\" ] && [ "$in_string" -eq 1 ]; then
            out+=$char
            escaped=1
            continue
        fi
        if [ "$char" = '"' ]; then
            out+=$char
            if [ "$in_string" -eq 1 ]; then
                in_string=0
            else
                in_string=1
            fi
            continue
        fi
        if [ "$char" = ";" ] && [ "$in_string" -eq 0 ]; then
            break
        fi
        out+=$char
    done
    printf '%s' "$out"
}

parse_byte() {
    local token=$1
    local line_no=$2
    if [[ ! $token =~ ^[0-9A-Fa-f]{2}$ ]]; then
        echo "line $line_no: invalid byte: $token" >&2
        exit 1
    fi
    printf '%d' "$((16#$token))"
}

parse_hex_word() {
    local token=$1
    local line_no=$2
    token=${token#0x}
    token=${token#0X}
    if [[ ! $token =~ ^[0-9A-Fa-f]+$ ]]; then
        echo "line $line_no: invalid hex word: $token" >&2
        exit 1
    fi
    local value=$((16#$token))
    if [ "$value" -lt 0 ] || [ "$value" -gt 65535 ]; then
        echo "line $line_no: word out of range: $token" >&2
        exit 1
    fi
    printf '%d' "$value"
}

check_word_value() {
    local value=$1
    local line_no=$2
    if [ "$value" -lt 0 ] || [ "$value" -gt 65535 ]; then
        echo "line $line_no: address out of 16-bit range: $value" >&2
        exit 1
    fi
}

parse_label() {
    local name=$1
    local line_no=$2
    if [[ ! $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo "line $line_no: invalid label: $name" >&2
        exit 1
    fi
}

ascii_payload() {
    local payload=$1
    local line_no=$2
    if [[ ! $payload =~ ^\".*\"$ ]]; then
        echo "line $line_no: ascii expects a quoted string" >&2
        exit 1
    fi
    payload=${payload#\"}
    payload=${payload%\"}
    printf '%s' "$payload"
}

ascii_size() {
    local payload=$1
    local expanded
    printf -v expanded '%b' "$payload"
    printf '%d' "${#expanded}"
}

emit_byte_value() {
    local value=$1
    printf '%b' "$(printf '\\x%02x' "$value")"
}

emit_word_le() {
    local value=$1
    emit_byte_value "$((value & 0xff))"
    emit_byte_value "$(((value >> 8) & 0xff))"
}

emit_bytes() {
    local token
    local line_no=$1
    shift
    for token in "$@"; do
        local value
        value=$(parse_byte "$token" "$line_no") || exit 1
        emit_byte_value "$value" >> "$TMP"
        OFFSET=$((OFFSET + 1))
    done
}

emit_ascii() {
    local payload=$1
    printf '%b' "$payload"
}

pad_to_offset() {
    local size=$1
    local byte=$2
    local line_no=$3
    local value
    value=$(parse_byte "$byte" "$line_no") || exit 1
    if [ "$OFFSET" -gt "$size" ]; then
        echo "line $line_no: output is $OFFSET bytes, cannot pad back to $size" >&2
        exit 1
    fi
    while [ "$OFFSET" -lt "$size" ]; do
        emit_byte_value "$value" >> "$TMP"
        OFFSET=$((OFFSET + 1))
    done
}

relative_value() {
    local label=$1
    local size=$2
    local line_no=$3
    local bits=$4
    if [ -z "${LABELS[$label]+set}" ]; then
        echo "line $line_no: unknown label: $label" >&2
        exit 1
    fi
    local next=$((ORIGIN + OFFSET + size))
    local rel=$((LABELS[$label] - next))
    local min max modulo
    if [ "$bits" -eq 8 ]; then
        min=-128
        max=127
        modulo=256
    else
        min=-32768
        max=32767
        modulo=65536
    fi
    if [ "$rel" -lt "$min" ] || [ "$rel" -gt "$max" ]; then
        echo "line $line_no: relative target out of range: $label" >&2
        exit 1
    fi
    if [ "$rel" -lt 0 ]; then
        rel=$((rel + modulo))
    fi
    printf '%d' "$rel"
}

process_line() {
    local mode=$1
    local line_no=$2
    local raw_line=$3
    local line directive rest
    line=$(trim "$(strip_comment "$raw_line")")
    [ -z "$line" ] && return
    [[ $line == raw\ * ]] && return
    [ "$line" = "}" ] && return

    read -r directive rest <<< "$line"
    rest=$(trim "${rest:-}")

    case "$directive" in
        origin)
            if [ "$ORIGIN_SET" -eq 1 ] || [ "$OFFSET" -ne 0 ] || { [ "$mode" = "measure" ] && [ "${#LABELS[@]}" -ne 0 ]; }; then
                echo "line $line_no: origin must appear before labels or emitted bytes" >&2
                exit 1
            fi
            ORIGIN=$(parse_hex_word "$rest" "$line_no") || exit 1
            ORIGIN_SET=1
            ;;
        label)
            parse_label "$rest" "$line_no"
            if [ "$mode" = "measure" ]; then
                if [ -n "${LABELS[$rest]+set}" ]; then
                    echo "line $line_no: duplicate label: $rest" >&2
                    exit 1
                fi
                local address=$((ORIGIN + OFFSET))
                check_word_value "$address" "$line_no"
                LABELS[$rest]=$address
            fi
            ;;
        bytes)
            # shellcheck disable=SC2086
            set -- $rest
            if [ "$mode" = "emit" ]; then
                emit_bytes "$line_no" "$@"
            else
                local token
                for token in "$@"; do
                    parse_byte "$token" "$line_no" >/dev/null
                    OFFSET=$((OFFSET + 1))
                done
            fi
            ;;
        byte)
            if [ "$mode" = "emit" ]; then
                emit_bytes "$line_no" "$rest"
            else
                parse_byte "$rest" "$line_no" >/dev/null
                OFFSET=$((OFFSET + 1))
            fi
            ;;
        addr16)
            parse_label "$rest" "$line_no"
            if [ "$mode" = "emit" ]; then
                if [ -z "${LABELS[$rest]+set}" ]; then
                    echo "line $line_no: unknown label: $rest" >&2
                    exit 1
                fi
                check_word_value "${LABELS[$rest]}" "$line_no"
                emit_word_le "${LABELS[$rest]}" >> "$TMP"
            fi
            OFFSET=$((OFFSET + 2))
            ;;
        rel8)
            parse_label "$rest" "$line_no"
            if [ "$mode" = "emit" ]; then
                local rel
                rel=$(relative_value "$rest" 1 "$line_no" 8) || exit 1
                emit_byte_value "$rel" >> "$TMP"
            fi
            OFFSET=$((OFFSET + 1))
            ;;
        rel16)
            parse_label "$rest" "$line_no"
            if [ "$mode" = "emit" ]; then
                local rel
                rel=$(relative_value "$rest" 2 "$line_no" 16) || exit 1
                emit_word_le "$rel" >> "$TMP"
            fi
            OFFSET=$((OFFSET + 2))
            ;;
        ascii)
            local payload size
            payload=$(ascii_payload "$rest" "$line_no") || exit 1
            size=$(ascii_size "$payload") || exit 1
            if [ "$mode" = "emit" ]; then
                emit_ascii "$payload" >> "$TMP"
            fi
            OFFSET=$((OFFSET + size))
            ;;
        pad_to)
            local size keyword byte extra
            read -r size keyword byte extra <<< "$rest"
            if [ "${keyword:-}" != "with" ] || [ -z "${byte:-}" ] || [ -n "${extra:-}" ]; then
                echo "line $line_no: expected pad_to <size> with <byte>" >&2
                exit 1
            fi
            if [[ ! $size =~ ^[0-9]+$ ]]; then
                echo "line $line_no: invalid pad size: $size" >&2
                exit 1
            fi
            if [ "$mode" = "emit" ]; then
                pad_to_offset "$size" "$byte" "$line_no"
            else
                parse_byte "$byte" "$line_no" >/dev/null
                if [ "$OFFSET" -gt "$size" ]; then
                    echo "line $line_no: output is $OFFSET bytes, cannot pad back to $size" >&2
                    exit 1
                fi
                OFFSET=$size
            fi
            ;;
        signature)
            # shellcheck disable=SC2086
            set -- $rest
            if [ "$mode" = "emit" ]; then
                emit_bytes "$line_no" "$@"
            else
                local token
                for token in "$@"; do
                    parse_byte "$token" "$line_no" >/dev/null
                    OFFSET=$((OFFSET + 1))
                done
            fi
            ;;
        *)
            echo "line $line_no: unknown directive: $directive" >&2
            exit 1
            ;;
    esac
}

process_source() {
    local mode=$1
    local line_no=0
    local raw_line
    ORIGIN=0
    ORIGIN_SET=0
    OFFSET=0
    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        line_no=$((line_no + 1))
        process_line "$mode" "$line_no" "$raw_line"
    done < "$SRC_COPY"
}

process_source measure
process_source emit

mkdir -p "$(dirname "$OUT")"
mv "$TMP" "$OUT"
trap - EXIT
