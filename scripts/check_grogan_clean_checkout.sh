#!/usr/bin/env bash
set -euo pipefail

# Build only from tracked HEAD material in two independent archive directories.
# This catches accidental dependence on build/, dist/, generated/, or an
# untracked local tool that a same-worktree reproducibility check cannot see.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
POISON="$ROOT/examples/grown-alpha/.clean-checkout-poison.$$.grw"
trap 'rm -rf "$TMP_DIR" "$POISON"' EXIT
fail() { echo "error: $1" >&2; exit 1; }
command -v git > /dev/null 2>&1 || fail 'git is required'
command -v tar > /dev/null 2>&1 || fail 'tar is required'
touch "$POISON"

for name in one two; do
    checkout="$TMP_DIR/$name"
    mkdir -p "$checkout"
    git -C "$ROOT" archive --format=tar HEAD | tar -xf - -C "$checkout"
    [ -f "$checkout/scripts/build_longmode_image.sh" ] || fail "$name archive is missing build scripts"
    (
        cd "$checkout"
        mkdir -p build
        bash scripts/grc0.sh examples/grown-alpha/hello.grw build/hello.gwo
        bash scripts/build_longmode_image.sh build/gros-longmode.img > /dev/null
        bash scripts/check_longmode_image.sh build/gros-longmode.img > /dev/null
        sha256sum build/hello.gwo build/gros-longmode.img > "$TMP_DIR/$name.manifest"
    )
done
cmp -s "$TMP_DIR/one.manifest" "$TMP_DIR/two.manifest" || fail 'isolated archive artifacts differ'
echo 'Grogan clean checkout: two git-archive builds reproduced compiler/image manifests'
