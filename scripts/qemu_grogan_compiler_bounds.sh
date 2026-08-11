#!/usr/bin/env bash
set -euo pipefail

# Run the in-OS Grown compiler against the exact identifier/string boundary
# corpus.  The validation user program is the parent process, so every case
# exercises the real process_spawn_args/process_wait path without monitor
# keyboard pacing or host-side compiler shortcuts.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
QEMU_TIMEOUT=${QEMU_TIMEOUT:-420}
TMP_DIR=$(mktemp -d)
QEMU_PID=
if [ "${KEEP_TMP:-0}" = 1 ]; then
    echo "artifacts: $TMP_DIR" >&2
    trap 'if [ -n "${QEMU_PID:-}" ]; then kill "$QEMU_PID" 2>/dev/null || true; fi' EXIT
else
    trap 'if [ -n "${QEMU_PID:-}" ]; then kill "$QEMU_PID" 2>/dev/null || true; fi; rm -rf "$TMP_DIR"' EXIT
fi
IMAGE="$TMP_DIR/compiler-bounds.img"
LOG="$TMP_DIR/debug.log"
MONITOR_LOG="$TMP_DIR/monitor.log"
FS_OFFSET=122880
FS_BLOCKS=192

fail() { echo "error: $1" >&2; exit 1; }
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'
CORPUS="$TMP_DIR/corpus"
"$ROOT/scripts/generate_grogan_compiler_corpus.sh" "$CORPUS" > /dev/null
corpus_expect() {
    awk -F '\t' -v fixture="$1" 'NR > 1 && $1 == fixture { print $4 }' "$CORPUS/manifest.tsv"
}
corpus_offset() {
    awk -F '\t' -v fixture="$1" 'NR > 1 && $1 == fixture { print $5 }' "$CORPUS/manifest.tsv"
}
corpus_bytes() {
    awk -F '\t' -v fixture="$1" 'NR > 1 && $1 == fixture { print $6 }' "$CORPUS/manifest.tsv"
}
corpus_status() {
    case "$(corpus_expect "$1")" in
        accept) printf '0' ;;
        reject) printf '5' ;;
        *) fail "missing compiler corpus expectation for $1" ;;
    esac
}
expected_id31_status=$(corpus_status id31)
expected_id32_status=$(corpus_status id32)
expected_id63_status=$(corpus_status id63)
expected_id64_status=$(corpus_status id64)
expected_str255_status=$(corpus_status str255)
expected_str256_status=$(corpus_status str256)
expected_yield_status=$(corpus_status yield)
offset_id31=$(corpus_offset id31); bytes_id31=$(corpus_bytes id31)
offset_id32=$(corpus_offset id32); bytes_id32=$(corpus_bytes id32)
offset_id63=$(corpus_offset id63); bytes_id63=$(corpus_bytes id63)
offset_id64=$(corpus_offset id64); bytes_id64=$(corpus_bytes id64)
offset_str255=$(corpus_offset str255); bytes_str255=$(corpus_bytes str255)
offset_str256=$(corpus_offset str256); bytes_str256=$(corpus_bytes str256)
offset_yield=$(corpus_offset yield); bytes_yield=$(corpus_bytes yield)

cat > "$TMP_DIR/validation-shell.grw" <<EOF
target "gros.x86.bios.longmode.grogan.v1"

fn append_text(destination: i32, position: i32, source: i32) -> i32 {
    let index: i32 = 0;
    while (0 < load_byte(source, index)) {
        store_byte(destination, position + index, load_byte(source, index));
        index = index + 1;
    }
    return position + index;
}

fn build_identifier(destination: i32, count: i32) -> i32 {
    let position: i32 = 0;
    position = append_text(destination, position, "target ");
    store_byte(destination, position, 34);
    position = position + 1;
    position = append_text(destination, position, "gros.x86.bios.longmode.grogan.v1");
    store_byte(destination, position, 34);
    position = position + 1;
    store_byte(destination, position, 10);
    position = position + 1;
    position = append_text(destination, position, "fn ");
    let name_start: i32 = position;
    let index: i32 = 0;
    while (index < count) {
        store_byte(destination, position + index, 97);
        index = index + 1;
    }
    position = position + count;
    position = append_text(destination, position, "() -> void {}");
    store_byte(destination, position, 10);
    position = position + 1;
    position = append_text(destination, position, "fn main() -> void { ");
    let copy: i32 = 0;
    while (copy < count) {
        store_byte(destination, position + copy, load_byte(destination, name_start + copy));
        copy = copy + 1;
    }
    position = position + count;
    position = append_text(destination, position, "(); }");
    store_byte(destination, position, 10);
    position = position + 1;
    store_byte(destination, position, 0);
    return position;
}

fn build_string(destination: i32, count: i32) -> i32 {
    let position: i32 = 0;
    position = append_text(destination, position, "target ");
    store_byte(destination, position, 34);
    position = position + 1;
    position = append_text(destination, position, "gros.x86.bios.longmode.grogan.v1");
    store_byte(destination, position, 34);
    position = position + 1;
    store_byte(destination, position, 10);
    position = position + 1;
    position = append_text(destination, position, "fn main() -> void { print_str(");
    store_byte(destination, position, 34);
    position = position + 1;
    let index: i32 = 0;
    while (index < count) {
        store_byte(destination, position + index, 115);
        index = index + 1;
    }
    position = position + count;
    store_byte(destination, position, 34);
    position = position + 1;
    position = append_text(destination, position, "); }");
    store_byte(destination, position, 10);
    position = position + 1;
    store_byte(destination, position, 0);
    return position;
}

fn build_yield(destination: i32) -> i32 {
    let position: i32 = 0;
    position = append_text(destination, position, "target ");
    store_byte(destination, position, 34);
    position = position + 1;
    position = append_text(destination, position, "gros.x86.bios.longmode.grogan.v1");
    store_byte(destination, position, 34);
    position = position + 1;
    store_byte(destination, position, 10);
    position = position + 1;
    position = append_text(destination, position, "fn main() -> void { task_yield(); }");
    store_byte(destination, position, 10);
    position = position + 1;
    store_byte(destination, position, 0);
    return position;
}

fn make_args(buffer: i32, source: i32, output: i32) -> i32 {
    let first: i32 = append_text(buffer, 0, source);
    store_byte(buffer, first, 0);
    let second: i32 = append_text(buffer, first + 1, output);
    store_byte(buffer, second, 0);
    return second + 1;
}

fn wait_child(pid: i32) -> i32 {
    let status: i32 = process_wait(pid);
    while (status < 0) {
        task_yield();
        status = process_wait(pid);
    }
    return status;
}

fn run_case(image: i32, size: i32, args: i32, source_path: i32, source: i32, source_size: i32, output: i32, expected: i32) -> i32 {
    let source_handle: i32 = path_create(source_path);
    if (source_handle < 0) { return 0; }
    let written: i32 = file_write(source_handle, source, source_size);
    file_close(source_handle);
    if (written < source_size) { file_unlink(source_path); return 0; }
    let args_size: i32 = make_args(args, source_path, output);
    let pid: i32 = process_spawn_args(image, size, args, args_size);
    if (pid < 0) { file_unlink(source_path); return 0; }
    let status: i32 = wait_child(pid);
    file_unlink(source_path);
    file_unlink(output);
    if (status == expected) { return 1; }
    return 0;
}

fn run_existing_case(image: i32, size: i32, args: i32, source_path: i32, source: i32, output: i32, expected: i32) -> i32 {
    let source_handle: i32 = file_open(source_path, 0);
    if (source_handle < 0) { return 0; }
    let source_size: i32 = file_read(source_handle, source, 4096);
    file_close(source_handle);
    if (source_size < 0) { return 0; }
    let args_size: i32 = make_args(args, source_path, output);
    let pid: i32 = process_spawn_args(image, size, args, args_size);
    if (pid < 0) { return 0; }
    let status: i32 = wait_child(pid);
    file_unlink(output);
    if (status == expected) { return 1; }
    return 0;
}

fn run_corpus_case(image: i32, size: i32, args: i32, corpus: i32, offset: i32, source_size: i32, source_path: i32, output: i32, expected: i32) -> i32 {
    let source_handle: i32 = path_create(source_path);
    if (source_handle < 0) { return 0; }
    let written: i32 = file_write(source_handle, corpus + offset, source_size);
    file_close(source_handle);
    if (written < source_size) { file_unlink(source_path); return 0; }
    let args_size: i32 = make_args(args, source_path, output);
    let pid: i32 = process_spawn_args(image, size, args, args_size);
    if (pid < 0) { file_unlink(source_path); return 0; }
    let status: i32 = wait_child(pid);
    file_unlink(source_path);
    file_unlink(output);
    if (status == expected) { return 1; }
    return 0;
}

fn main() -> void {
    let handle: i32 = file_open("grc1.gwo", 0);
    let image: i32 = mem_grow(4096);
    let image_page1: i32 = mem_grow(4096);
    let image_page2: i32 = mem_grow(4096);
    let image_page3: i32 = mem_grow(4096);
    let image_page4: i32 = mem_grow(4096);
    let size: i32 = file_read(handle, image, 16432);
    file_close(handle);
    let args: i32 = mem_grow(4096);
    let source: i32 = mem_grow(4096);
    let corpus_handle: i32 = file_open("corpus.grw", 0);
    let corpus: i32 = mem_grow(4096);
    let corpus_size: i32 = file_read(corpus_handle, corpus, 4096);
    file_close(corpus_handle);
    let ok: i32 = 1;
    if (corpus_size < 0) { ok = 0; }
    if (run_corpus_case(image, size, args, corpus, $offset_id31, $bytes_id31, "shared-id31.grw", "shared-id31.gwo", $expected_id31_status) == 1) { ok = ok; } else { ok = 0; }
    if (run_corpus_case(image, size, args, corpus, $offset_id32, $bytes_id32, "shared-id32.grw", "shared-id32.gwo", $expected_id32_status) == 1) { ok = ok; } else { ok = 0; }
    if (run_corpus_case(image, size, args, corpus, $offset_id63, $bytes_id63, "shared-id63.grw", "shared-id63.gwo", $expected_id63_status) == 1) { ok = ok; } else { ok = 0; }
    if (run_corpus_case(image, size, args, corpus, $offset_id64, $bytes_id64, "shared-id64.grw", "shared-id64.gwo", $expected_id64_status) == 1) { ok = ok; } else { ok = 0; }
    if (run_corpus_case(image, size, args, corpus, $offset_str255, $bytes_str255, "shared-str255.grw", "shared-str255.gwo", $expected_str255_status) == 1) { ok = ok; } else { ok = 0; }
    if (run_corpus_case(image, size, args, corpus, $offset_str256, $bytes_str256, "shared-str256.grw", "shared-str256.gwo", $expected_str256_status) == 1) { ok = ok; } else { ok = 0; }
    if (run_corpus_case(image, size, args, corpus, $offset_yield, $bytes_yield, "shared-yield.grw", "shared-yield.gwo", $expected_yield_status) == 1) { ok = ok; } else { ok = 0; }
    let source_size: i32 = build_identifier(source, 31);
    if (run_case(image, size, args, "id31.grw", source, source_size, "id31.gwo", 0) == 1) { ok = ok; } else { ok = 0; }
    source_size = build_identifier(source, 32);
    if (run_case(image, size, args, "id32.grw", source, source_size, "id32.gwo", 5) == 1) { ok = ok; } else { ok = 0; }
    source_size = build_identifier(source, 63);
    if (run_case(image, size, args, "id63.grw", source, source_size, "id63.gwo", 5) == 1) { ok = ok; } else { ok = 0; }
    source_size = build_identifier(source, 64);
    if (run_case(image, size, args, "id64.grw", source, source_size, "id64.gwo", 5) == 1) { ok = ok; } else { ok = 0; }
    source_size = build_string(source, 255);
    if (run_case(image, size, args, "str255.grw", source, source_size, "str255.gwo", 0) == 1) { ok = ok; } else { ok = 0; }
    source_size = build_string(source, 256);
    if (run_case(image, size, args, "str256.grw", source, source_size, "str256.gwo", 5) == 1) { ok = ok; } else { ok = 0; }
    source_size = build_yield(source);
    if (run_case(image, size, args, "yield.grw", source, source_size, "yield.gwo", 0) == 1) { ok = ok; } else { ok = 0; }
    if (ok == 1) { print_str("BOUNDSOK\\n"); } else { print_str("BOUNDSBAD\\n"); }
    exit(0);
}
EOF

GROGAN_USER_SOURCE="$TMP_DIR/validation-shell.grw" \
    "$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TMP_DIR/gfs2"
"$TMP_DIR/gfs2" put "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" corpus.grw "$CORPUS/corpus.grw" > /dev/null
"$TMP_DIR/gfs2" check "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" > /dev/null

qemu-system-x86_64 \
    -drive format=raw,file="$IMAGE" \
    -display none -monitor none -no-reboot -no-shutdown \
    -debugcon "file:$LOG" -global isa-debugcon.iobase=0xe9 \
    > "$MONITOR_LOG" 2>&1 &
QEMU_PID=$!
deadline=$((SECONDS + QEMU_TIMEOUT))
while kill -0 "$QEMU_PID" 2>/dev/null; do
    if [ -f "$LOG" ] && grep -aF 'BOUNDSOK' "$LOG" > /dev/null && grep -aF 'USEROK' "$LOG" > /dev/null; then
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

grep -aF 'BOUNDSOK' "$LOG" > /dev/null || fail 'in-OS compiler boundary corpus failed'
grep -aF 'USEROK' "$LOG" > /dev/null || fail 'kernel recovery marker missing'
grep -aF 'BOUNDSBAD' "$LOG" > /dev/null && fail 'in-OS compiler reported a boundary mismatch'
echo 'Grogan compiler bounds: shared corpus matches Rust accept/reject at identifier 31/32/63/64, string 255/256, and task_yield'
