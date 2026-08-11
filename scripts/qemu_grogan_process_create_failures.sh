#!/usr/bin/env bash
set -euo pipefail

# Validation-only transactional process-create campaign.  The test image arms
# a one-shot countdown after the two boot processes exist: child attempt N
# fails at allocation N, so one QEMU boot covers every allocation edge and then
# proves that the reusable child succeeds on the first attempt beyond N.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
ATTEMPTS=${ATTEMPTS:-96}
QEMU_TIMEOUT=${QEMU_TIMEOUT:-600}
EXPECTED_ATTEMPTS=$((ATTEMPTS + 1))
TMP_DIR=$(mktemp -d)
QEMU_PID=
if [ "${KEEP_TMP:-0}" = 1 ]; then
    echo "artifacts: $TMP_DIR" >&2
    trap 'if [ -n "${QEMU_PID:-}" ]; then kill "$QEMU_PID" 2>/dev/null || true; fi' EXIT
else
    trap 'if [ -n "${QEMU_PID:-}" ]; then kill "$QEMU_PID" 2>/dev/null || true; fi; rm -rf "$TMP_DIR"' EXIT
fi
IMAGE="$TMP_DIR/process-create-failures.img"
LOG="$TMP_DIR/debug.log"
MONITOR_LOG="$TMP_DIR/monitor.log"
FS_OFFSET=122880
FS_BLOCKS=192

fail() { echo "error: $1" >&2; exit 1; }
count_marker() {
    local marker=$1
    [ -f "$LOG" ] || { echo 0; return; }
    (grep -ao "$marker" "$LOG" || true) | wc -l | tr -d ' '
}
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'
[[ "$ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || fail 'ATTEMPTS must be a positive integer'

cat > "$TMP_DIR/process-create-shell.grw" <<EOF
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
    let status_handle: i32 = file_open("exit-status.gwo", 0);
    let status_image: i32 = mem_grow(4096);
    let status_size: i32 = file_read(status_handle, status_image, 4096);
    file_close(status_handle);
    let attempt: i32 = 0;
    let failures: i32 = 0;
    let zero_status_ok: i32 = 1;
    while (attempt < $ATTEMPTS) {
        let pid: i32 = process_spawn(image, size);
        if (pid < 0) {
            failures = failures + 1;
        } else {
            let status: i32 = wait_child(pid);
            if (status == 0) {
                zero_status_ok = 1;
            } else {
                zero_status_ok = 0;
            }
        }
        attempt = attempt + 1;
    }
    let status_pid: i32 = process_spawn(status_image, status_size);
    if (status_pid < 0) {
        print_str("WAITBAD\\n");
    } else {
        let nonzero_status: i32 = wait_child(status_pid);
        if (zero_status_ok == 1) {
            if (nonzero_status == 37) {
                print_str("WAITOK\\n");
            } else {
                print_str("WAITBAD\\n");
            }
        } else {
            print_str("WAITBAD\\n");
        }
    }
    print_str("PCTEST ");
    print_i32(failures);
    print_str("\\n");
    exit(0);
}
EOF

GROGAN_USER_SOURCE="$TMP_DIR/process-create-shell.grw" \
LONGMODE_NASM_DEFINE=PROCESS_CREATE_TEST=1 \
    "$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null

"$ROOT/scripts/grc0.sh" \
    "$ROOT/examples/grown-alpha/hello.grw" "$TMP_DIR/hello.gwo"
cat > "$TMP_DIR/exit-status.grw" <<'EOF'
target "gros.x86.bios.longmode.grogan.v1"
fn main() -> void { exit(37); }
EOF
"$ROOT/scripts/grc0.sh" \
    "$TMP_DIR/exit-status.grw" "$TMP_DIR/exit-status.gwo"
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TMP_DIR/gfs2"
"$TMP_DIR/gfs2" put "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" hello.gwo "$TMP_DIR/hello.gwo"
"$TMP_DIR/gfs2" put "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" exit-status.gwo "$TMP_DIR/exit-status.gwo"
"$TMP_DIR/gfs2" check "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" > /dev/null

qemu-system-x86_64 \
    -drive format=raw,file="$IMAGE" \
    -display none -monitor none -no-reboot -no-shutdown \
    -debugcon "file:$LOG" -global isa-debugcon.iobase=0xe9 \
    > "$MONITOR_LOG" 2>&1 &
QEMU_PID=$!
deadline=$((SECONDS + QEMU_TIMEOUT))
while kill -0 "$QEMU_PID" 2>/dev/null; do
    if [ "$(count_marker PCA)" -ge "$ATTEMPTS" ] && \
       [ -f "$LOG" ] && grep -aF 'PCTEST ' "$LOG" > /dev/null && \
       grep -aF 'USEROK' "$LOG" > /dev/null; then
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

attempt_markers=$(count_marker PCA)
failure_markers=$(count_marker PCF)
success_markers=$(count_marker PCS)
[ "$attempt_markers" = "$EXPECTED_ATTEMPTS" ] || fail "process-create attempts $attempt_markers/$EXPECTED_ATTEMPTS"
[ "$failure_markers" -gt 0 ] || fail 'no injected process-create failure observed'
[ "$success_markers" -gt 0 ] || fail 'no post-failure process-create success observed'
[ "$((failure_markers + success_markers))" = "$EXPECTED_ATTEMPTS" ] || \
    fail "attempt outcomes do not partition: failures=$failure_markers successes=$success_markers"
grep -aF -- '-16' "$LOG" > /dev/null && fail 'reusable child returned EBUSY after injected failure'
grep -aF 'USEROK' "$LOG" > /dev/null || fail 'kernel recovery marker missing'
grep -aF 'GRC FAIL' "$LOG" > /dev/null && fail 'compiler unexpectedly failed during rollback campaign'
grep -aF 'PCTEST ' "$LOG" > /dev/null || fail 'program did not complete the process-create loop'
grep -aF 'WAITOK' "$LOG" > /dev/null || fail 'process_wait did not preserve zero/nonzero exit status'

echo "Grogan process-create failures: $failure_markers allocation edges rolled back and child reuse succeeded"
