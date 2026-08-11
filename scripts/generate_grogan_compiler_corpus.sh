#!/usr/bin/env bash
set -euo pipefail

# Generate the boundary corpus consumed by both the host compiler lane and the
# in-OS compiler lane. Keeping the source bytes in one producer prevents the
# two lanes from silently testing different fixtures.
OUT=${1:?usage: generate_grogan_compiler_corpus.sh OUTPUT_DIR}
mkdir -p "$OUT"

repeat_char() {
    local count=$1 char=$2 value=
    for ((index = 0; index < count; index++)); do value+="$char"; done
    printf '%s' "$value"
}

TARGET='gros.x86.bios.longmode.grogan.v1'
id_source() {
    local name=$1
    printf 'target "%s"\nfn %s() -> void {}\nfn main() -> void { %s(); }\n' \
        "$TARGET" "$name" "$name"
}
string_source() {
    local value=$1
    printf 'target "%s"\nfn main() -> void { print_str("%s"); }\n' \
        "$TARGET" "$value"
}

id31=$(repeat_char 31 a)
id32=$(repeat_char 32 a)
id63=$(repeat_char 63 a)
id64=$(repeat_char 64 a)
str255=$(repeat_char 255 s)
str256=$(repeat_char 256 s)

id_source "$id31" > "$OUT/id31.grw"
id_source "$id32" > "$OUT/id32.grw"
id_source "$id63" > "$OUT/id63.grw"
id_source "$id64" > "$OUT/id64.grw"
string_source "$str255" > "$OUT/str255.grw"
string_source "$str256" > "$OUT/str256.grw"
printf 'target "%s"\nfn main() -> void { task_yield(); }\n' "$TARGET" > "$OUT/yield.grw"

corpus="$OUT/corpus.grw"
: > "$corpus"
offset=0
{
    printf 'name\tclass\tlength\texpect\toffset\tbytes\n'
    for name in id31 id32 id63 id64 str255 str256 yield; do
        case "$name" in
            id31) class=identifier; length=31; expect=accept ;;
            id32) class=identifier; length=32; expect=reject ;;
            id63) class=identifier; length=63; expect=reject ;;
            id64) class=identifier; length=64; expect=reject ;;
            str255) class=string; length=255; expect=accept ;;
            str256) class=string; length=256; expect=reject ;;
            yield) class=void-import; length=0; expect=accept ;;
        esac
        bytes=$(wc -c < "$OUT/$name.grw" | tr -d ' ')
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$class" "$length" "$expect" "$offset" "$bytes"
        cat "$OUT/$name.grw" >> "$corpus"
        offset=$((offset + bytes))
    done
} > "$OUT/manifest.tsv"

echo "Grogan compiler corpus: generated 7 shared fixtures in $OUT"
