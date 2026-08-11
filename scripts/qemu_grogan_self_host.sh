#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
FS_OFFSET=122880
FS_BLOCKS=192
WAIT_AFTER_FIRST=${WAIT_AFTER_FIRST:-35}
WAIT_AFTER_SECOND=${WAIT_AFTER_SECOND:-35}
QEMU_TIMEOUT=${QEMU_TIMEOUT:-100}

fail() { echo "error: $1" >&2; exit 1; }
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'

send_key() {
    printf 'sendkey %s\n' "$1"
    sleep 0.08
}

send_text() {
    local text=$1 index key
    for ((index = 0; index < ${#text}; index++)); do
        key=${text:index:1}
        case "$key" in
            ' ') key=spc ;;
            '.') key=dot ;;
            '-') key=minus ;;
            '/') key=slash ;;
        esac
        send_key "$key"
    done
    send_key ret
}

run_clean_boot() {
    local run_id=$1 run_dir image log monitor
    run_dir="$ROOT/build/self-host-qemu/run-$run_id"
    rm -rf "$run_dir"
    mkdir -p "$run_dir"
    image="$run_dir/self-host.img"
    log="$run_dir/debug.log"
    monitor="$run_dir/monitor.log"
    GROGAN_USER_SOURCE="$ROOT/examples/grown-alpha/user-shell.grw" \
        "$ROOT/scripts/build_longmode_image.sh" "$image" > /dev/null

    set +e
    {
        sleep 5
        send_text 'grc grc1.grw grc2.gwo'
        sleep "$WAIT_AFTER_FIRST"
        send_text 'run grc2.gwo grc1.grw grc3.gwo'
        sleep "$WAIT_AFTER_SECOND"
        send_text 'exit'
        sleep 2
        printf 'quit\n'
    } | timeout "$QEMU_TIMEOUT" qemu-system-x86_64 \
        -drive format=raw,file="$image" \
        -display none \
        -monitor stdio \
        -no-reboot \
        -no-shutdown \
        -debugcon "file:$log" \
        -global isa-debugcon.iobase=0xe9 \
        > "$monitor" 2>&1
    local status=$?
    set -e
    [ "$status" = 0 ] || { tail -c 4000 "$monitor" >&2; fail "qemu clean boot $run_id status $status"; }
    grep -aF 'GrOS user shell' "$log" > /dev/null || fail "shell missing on clean boot $run_id"
    grep -aF 'USEROK' "$log" > /dev/null || fail "kernel recovery missing on clean boot $run_id"
    grep -aF 'GRC FAIL' "$log" > /dev/null && fail "first in-OS compiler failed on clean boot $run_id"
    grep -aF 'RUN FAIL' "$log" > /dev/null && fail "second in-OS compiler failed on clean boot $run_id"
    grep -aF 'OK' "$log" > /dev/null || fail "fixed-point commands did not report OK on clean boot $run_id"

    "$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$run_dir/gfs2"
    "$run_dir/gfs2" check "$image" "$FS_OFFSET" "$FS_BLOCKS" > /dev/null
    "$run_dir/gfs2" get "$image" "$FS_OFFSET" "$FS_BLOCKS" grc2.gwo "$run_dir/grc2.gwo"
    "$run_dir/gfs2" get "$image" "$FS_OFFSET" "$FS_BLOCKS" grc3.gwo "$run_dir/grc3.gwo"
    sha256sum "$run_dir/grc2.gwo" | cut -d ' ' -f 1 > "$run_dir/grc2.sha256"
    sha256sum "$run_dir/grc3.gwo" | cut -d ' ' -f 1 > "$run_dir/grc3.sha256"
    cmp "$run_dir/grc2.sha256" "$run_dir/grc3.sha256" || fail "grc2/grc3 differ on clean boot $run_id"
    echo "clean boot $run_id fixed point: $(cat "$run_dir/grc2.sha256")"
}

run_clean_boot 1
run_clean_boot 2
cmp "$ROOT/build/self-host-qemu/run-1/grc2.sha256" \
    "$ROOT/build/self-host-qemu/run-2/grc2.sha256" || fail 'clean boot artifacts differ'
echo 'Grogan self-host: grc1 -> grc2 -> grc3 byte equality reproduced on two clean boots'
