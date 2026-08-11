#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
CORPUS="$TMP_DIR/corpus"
"$ROOT/scripts/generate_grogan_compiler_corpus.sh" "$CORPUS" > /dev/null

fail() { echo "error: $1" >&2; exit 1; }
while IFS=$'\t' read -r name class length expected offset bytes; do
    source="$CORPUS/$name.grw"
    output="$TMP_DIR/$name.gwo"
    if "$ROOT/scripts/grc0.sh" "$source" "$output" > "$TMP_DIR/$name.stdout" 2> "$TMP_DIR/$name.stderr"; then
        actual=accept
    else
        actual=reject
    fi
    [ "$actual" = "$expected" ] || fail "$name: expected $expected, got $actual"
    if [ "$expected" = accept ]; then
        [ -s "$output" ] || fail "$name: accepted source produced no artifact"
    else
        [ ! -s "$output" ] || fail "$name: rejected source produced an artifact"
    fi
done < <(tail -n +2 "$CORPUS/manifest.tsv")

echo 'Grogan compiler corpus: shared identifier/string/task_yield fixtures match Rust accept/reject contract'
