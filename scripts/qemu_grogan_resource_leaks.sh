#!/usr/bin/env bash
set -euo pipefail

# Prove that repeated spawn/wait/reap cycles return owned frame and handle
# counts to one baseline. Counters exist only in RESOURCE_TEST images; the
# release image has no instrumentation or altered allocation policy.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
CYCLES=${CYCLES:-100}
QEMU_TIMEOUT=${QEMU_TIMEOUT:-240}
TMP_DIR=$(mktemp -d)
QEMU_PID=
if [ "${KEEP_TMP:-0}" = 1 ]; then
    echo "artifacts: $TMP_DIR" >&2
    trap 'if [ -n "${QEMU_PID:-}" ]; then kill "$QEMU_PID" 2>/dev/null || true; fi' EXIT
else
    trap 'if [ -n "${QEMU_PID:-}" ]; then kill "$QEMU_PID" 2>/dev/null || true; fi; rm -rf "$TMP_DIR"' EXIT
fi
IMAGE="$TMP_DIR/resource-leaks.img"
LOG="$TMP_DIR/debug.log"
MONITOR_LOG="$TMP_DIR/monitor.log"
FS_OFFSET=122880
FS_BLOCKS=192

fail() { echo "error: $1" >&2; exit 1; }
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'
[[ "$CYCLES" =~ ^[1-9][0-9]*$ ]] || fail 'CYCLES must be a positive integer'

cat > "$TMP_DIR/resource-shell.grw" <<EOF
target "gros.x86.bios.longmode.grogan.v1"

fn wait_child(pid: i32) -> i32 {
    let status: i32 = process_wait(pid);
    while (status < 0) {
        task_yield();
        status = process_wait(pid);
    }
    return status;
}

fn main() -> void {
    let handle: i32 = file_open("hello.gwo", 0);
    let image: i32 = mem_grow(4096);
    let size: i32 = file_read(handle, image, 4096);
    file_close(handle);
    let cycle: i32 = 0;
    while (cycle < $CYCLES) {
        let open_handle: i32 = file_open("hello.gwo", 0);
        file_close(open_handle);
        let pid: i32 = process_spawn(image, size);
        if (pid < 0) {
            print_str("LEAKBAD\\n");
            exit(1);
        } else {
            wait_child(pid);
        }
        cycle = cycle + 1;
    }
    print_str("LEAKTEST\\n");
    exit(0);
}
EOF

GROGAN_USER_SOURCE="$TMP_DIR/resource-shell.grw" \
LONGMODE_NASM_DEFINE=RESOURCE_TEST=1 \
    "$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
"$ROOT/scripts/grc0.sh" "$ROOT/examples/grown-alpha/hello.grw" "$TMP_DIR/hello.gwo" > /dev/null
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TMP_DIR/gfs2"
"$TMP_DIR/gfs2" put "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" hello.gwo "$TMP_DIR/hello.gwo"
"$TMP_DIR/gfs2" check "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" > /dev/null

qemu-system-x86_64 \
    -drive format=raw,file="$IMAGE" \
    -display none -monitor none -no-reboot -no-shutdown \
    -debugcon "file:$LOG" -global isa-debugcon.iobase=0xe9 \
    > "$MONITOR_LOG" 2>&1 &
QEMU_PID=$!
deadline=$((SECONDS + QEMU_TIMEOUT))
while kill -0 "$QEMU_PID" 2>/dev/null; do
    if [ -f "$LOG" ] && grep -aF 'LEAKTEST' "$LOG" > /dev/null && grep -aF 'USEROK' "$LOG" > /dev/null; then
        kill "$QEMU_PID" 2>/dev/null || true
        break
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
        kill "$QEMU_PID" 2>/dev/null || true
        tail -c 6000 "$MONITOR_LOG" >&2
        fail 'qemu timeout'
    fi
    sleep 0.1
done
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=

grep -aF 'LEAKTEST' "$LOG" > /dev/null || fail 'resource loop did not complete'
grep -aF 'LEAKBAD' "$LOG" > /dev/null && fail 'resource loop reported a process failure'
grep -aF 'USEROK' "$LOG" > /dev/null || fail 'kernel recovery marker missing'
mapfile -t snapshots < <(grep -aoE 'R[0-9A-F]{8}H[0-9A-F]{8}P[0-9A-F]{8}' "$LOG" || true)
expected=$((CYCLES + 2))
[ "${#snapshots[@]}" = "$expected" ] || fail "resource snapshots ${#snapshots[@]}/$expected"
[[ "${snapshots[0]}" =~ ^R[0-9A-F]{8}H00000000P[0-9A-F]{8}$ ]] || fail "unexpected bootstrap snapshot: ${snapshots[0]}"
baseline=${snapshots[1]}
[[ "$baseline" =~ ^R[0-9A-F]{8}H00000000P[0-9A-F]{8}$ ]] || fail "unexpected baseline snapshot: $baseline"
baseline_counts=${baseline:0:18}
for ((index = 2; index <= CYCLES; index++)); do
    current_counts=${snapshots[index]:0:18}
    [ "$current_counts" = "$baseline_counts" ] || fail "resource baseline changed at cycle $((index + 1)) owner_pid=${snapshots[index]:19:8}: ${snapshots[index]}"
done
final_index=$((CYCLES + 1))
[[ "${snapshots[final_index]:0:18}" = R00000000H00000000 ]] || fail "final process cleanup snapshot is not zero owner_pid=${snapshots[final_index]:19:8}: ${snapshots[final_index]}"

echo "Grogan resource leaks: $CYCLES spawn/wait/reap cycles returned frames and handles to baseline"
