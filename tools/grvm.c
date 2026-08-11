#define _POSIX_C_SOURCE 200809L
#include "gwo2.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static uint16_t get16(const uint8_t *p) { return (uint16_t)p[0] | (uint16_t)p[1] << 8; }
static int fail(const char *message) { fprintf(stderr, "error: %s\n", message); return 1; }

enum { VM_MEMORY_SIZE = 1 << 20, VM_MAX_HANDLES = 16, VM_MAX_FRAMES = 64 };

typedef struct {
    uint32_t return_pc;
    uint32_t base;
    uint8_t result;
    int64_t locals[64];
} vm_frame_t;

static int memory_span(uint64_t pointer, uint64_t size) {
    return pointer < VM_MEMORY_SIZE && size <= VM_MEMORY_SIZE - pointer;
}

static int read_string(const uint8_t *memory, uint64_t pointer, char *out, size_t out_size) {
    if (!memory_span(pointer, 1) || out_size == 0) return 0;
    for (size_t i = 0; i + 1 < out_size && pointer + i < VM_MEMORY_SIZE; ++i) {
        out[i] = (char)memory[pointer + i];
        if (out[i] == '\0') return 1;
    }
    return 0;
}

static int run(const gwo2_image_t *image, uint64_t limit) {
    int64_t stack[1024];
    vm_frame_t frames[VM_MAX_FRAMES] = {0};
    uint8_t memory[VM_MEMORY_SIZE] = {0};
    FILE *handles[VM_MAX_HANDLES] = {0};
    uint64_t heap = 0x1000;
    uint32_t sp = 0;
    uint32_t fp = 0;
    uint32_t pc = image->entry_offset;
    uint64_t steps = 0;
    while (pc < image->code_size && steps++ < limit) {
        uint8_t op = image->code[pc++];
        switch (op) {
        case 1: /* const_i32 */
            if (pc + 4 > image->code_size || sp >= 1024) return fail("GWO2 VM constant/stack fault");
            stack[sp++] = (int32_t)((uint32_t)image->code[pc] | (uint32_t)image->code[pc + 1] << 8 |
                                    (uint32_t)image->code[pc + 2] << 16 | (uint32_t)image->code[pc + 3] << 24);
            pc += 4;
            break;
        case 2: { /* load_local */
            if (pc >= image->code_size || image->code[pc] >= 64 || sp >= 1024) return fail("GWO2 VM local fault");
            stack[sp++] = frames[fp].locals[image->code[pc++]];
            break;
        }
        case 3: /* store_local */
            if (pc >= image->code_size || image->code[pc] >= 64 || sp == 0) return fail("GWO2 VM local store fault");
            frames[fp].locals[image->code[pc++]] = stack[--sp];
            break;
        case 15: { /* const_bytes: copy a NUL-terminated literal into VM memory */
            if (pc >= image->code_size) return fail("GWO2 VM byte constant fault");
            uint32_t length = image->code[pc++];
            if (pc + length > image->code_size || sp >= 1024 || !memory_span(heap, length + 1))
                return fail("GWO2 VM byte constant/memory fault");
            memcpy(memory + heap, image->code + pc, length);
            memory[heap + length] = 0;
            stack[sp++] = (int64_t)heap;
            heap += length + 1;
            pc += length;
            break;
        }
        case 16: { /* load_byte(pointer, index) */
            if (sp < 2 || stack[sp - 1] < 0 || stack[sp - 2] < 0) return fail("GWO2 VM byte load stack fault");
            uint64_t pointer = (uint64_t)stack[sp - 2], index = (uint64_t)stack[sp - 1];
            if (index >= VM_MEMORY_SIZE || !memory_span(pointer + index, 1)) return fail("GWO2 VM byte load bounds fault");
            stack[sp - 2] = memory[pointer + index];
            --sp;
            break;
        }
        case 17: { /* store_byte(pointer, index, value) */
            if (sp < 3 || stack[sp - 1] < 0 || stack[sp - 2] < 0) return fail("GWO2 VM byte store stack fault");
            uint64_t pointer = (uint64_t)stack[sp - 3], index = (uint64_t)stack[sp - 2];
            if (index >= VM_MEMORY_SIZE || !memory_span(pointer + index, 1)) return fail("GWO2 VM byte store bounds fault");
            memory[pointer + index] = (uint8_t)stack[sp - 1];
            sp -= 3;
            break;
        }
        case 18: /* duplicate */
            if (sp == 0 || sp >= 1024) return fail("GWO2 VM duplicate stack fault");
            stack[sp] = stack[sp - 1];
            ++sp;
            break;
        case 19: /* drop */
            if (sp == 0) return fail("GWO2 VM drop stack fault");
            --sp;
            break;
        case 4: case 5: case 6: case 7: case 8: case 9: {
            if (sp < 2) return fail("GWO2 VM arithmetic stack fault");
            int64_t rhs = stack[--sp], lhs = stack[--sp], value = 0;
            if (op == 4) value = lhs + rhs;
            else if (op == 5) value = lhs - rhs;
            else if (op == 6) value = lhs * rhs;
            else if (op == 7) { if (rhs == 0) return fail("GWO2 VM division by zero"); value = lhs / rhs; }
            else if (op == 8) value = lhs == rhs;
            else value = lhs < rhs;
            stack[sp++] = value;
            break;
        }
        case 10: { /* jump */
            if (pc + 2 > image->code_size) return fail("GWO2 VM jump encoding fault");
            int16_t delta = (int16_t)get16(image->code + pc);
            int64_t target = (int64_t)pc + 2 + delta;
            if (target < 0 || target >= image->code_size) return fail("GWO2 VM jump target fault");
            pc = (uint32_t)target;
            break;
        }
        case 11: { /* jump_if_zero */
            if (pc + 2 > image->code_size || sp == 0) return fail("GWO2 VM conditional jump fault");
            int64_t value = stack[--sp];
            int16_t delta = (int16_t)get16(image->code + pc);
            pc += 2;
            if (value == 0) {
                int64_t target = (int64_t)pc + delta;
                if (target < 0 || target >= image->code_size) return fail("GWO2 VM conditional target fault");
                pc = (uint32_t)target;
            }
            break;
        }
        case 12: { /* import(id, argc) */
            if (pc + 2 > image->code_size) return fail("GWO2 VM import encoding fault");
            uint8_t id = image->code[pc++], argc = image->code[pc++];
            if (argc > sp) return fail("GWO2 VM import stack fault");
            if (id == 1 && argc == 1) {
                printf("%" PRId64 "\n", stack[--sp]);
            } else if (id == 2 && argc == 1) {
                int status = (int)stack[--sp];
                return status;
            } else if (id == 3 && argc == 0) {
                putchar('\n');
            } else if (id == 4 && argc == 2) {
                uint64_t count = stack[--sp], pointer = stack[--sp];
                if (!memory_span(pointer, count)) return fail("GWO2 VM console read bounds fault");
                /* Hosted tests remain deterministic: stdin is intentionally not
                   consumed by the reference runner. */
                (void)count;
                stack[sp++] = 0;
            } else if (id == 5 && argc == 2) {
                int64_t flags = stack[--sp];
                uint64_t pointer = (uint64_t)stack[--sp];
                char path[256];
                if (flags < 0 || !read_string(memory, pointer, path, sizeof(path))) return fail("GWO2 VM open path fault");
                const char *mode = (flags & 1) ? "wb+" : "rb";
                FILE *file = fopen(path, mode);
                if (!file) { stack[sp++] = -2; break; }
                int handle = 0;
                for (int i = 1; i < VM_MAX_HANDLES; ++i) if (!handles[i]) { handle = i; handles[i] = file; break; }
                if (!handle) { fclose(file); stack[sp++] = -24; }
                else stack[sp++] = handle;
            } else if (id == 6 && argc == 3) {
                uint64_t count = stack[--sp], pointer = (uint64_t)stack[--sp];
                int64_t handle = stack[--sp];
                if (handle <= 0 || handle >= VM_MAX_HANDLES || !handles[handle] || !memory_span(pointer, count)) return fail("GWO2 VM read bounds/handle fault");
                size_t n = fread(memory + pointer, 1, (size_t)count, handles[handle]);
                stack[sp++] = (int64_t)n;
            } else if (id == 7 && argc == 3) {
                uint64_t count = stack[--sp], pointer = (uint64_t)stack[--sp];
                int64_t handle = stack[--sp];
                if (handle <= 0 || handle >= VM_MAX_HANDLES || !handles[handle] || !memory_span(pointer, count)) return fail("GWO2 VM write bounds/handle fault");
                size_t n = fwrite(memory + pointer, 1, (size_t)count, handles[handle]);
                fflush(handles[handle]);
                stack[sp++] = (int64_t)n;
            } else if (id == 8 && argc == 1) {
                int64_t handle = stack[--sp];
                if (handle <= 0 || handle >= VM_MAX_HANDLES || !handles[handle]) { stack[sp++] = -9; break; }
                fclose(handles[handle]); handles[handle] = NULL; stack[sp++] = 0;
            } else if (id == 9 && argc == 2) {
                uint64_t stat_pointer = (uint64_t)stack[--sp];
                int64_t handle = stack[--sp];
                if (handle <= 0 || handle >= VM_MAX_HANDLES || !handles[handle] || !memory_span(stat_pointer, 16)) return fail("GWO2 VM stat bounds/handle fault");
                long current = ftell(handles[handle]);
                if (fseek(handles[handle], 0, SEEK_END) != 0) return fail("GWO2 VM stat seek fault");
                long size = ftell(handles[handle]);
                if (current >= 0) (void)fseek(handles[handle], current, SEEK_SET);
                if (size < 0) return fail("GWO2 VM stat size fault");
                uint64_t value = (uint64_t)size;
                memcpy(memory + stat_pointer, &value, sizeof(value));
                uint32_t mode = 0644;
                memcpy(memory + stat_pointer + 8, &mode, sizeof(mode));
                memset(memory + stat_pointer + 12, 0, 4);
                stack[sp++] = 0;
            } else if (id == 10 && argc == 1) {
                int64_t amount = stack[--sp];
                if (amount < 0 || amount > 4096 || !memory_span(heap, (uint64_t)amount)) return fail("GWO2 VM memory grow fault");
                stack[sp++] = (int64_t)heap; heap += (uint64_t)amount;
            } else if (id == 11 && argc == 1) {
                uint64_t pointer = (uint64_t)stack[--sp];
                char path[256];
                if (!read_string(memory, pointer, path, sizeof(path))) return fail("GWO2 VM create path fault");
                FILE *file = fopen(path, "wb+");
                if (!file) { stack[sp++] = -5; break; }
                int handle = 0;
                for (int i = 1; i < VM_MAX_HANDLES; ++i) if (!handles[i]) { handle = i; handles[i] = file; break; }
                if (!handle) { fclose(file); stack[sp++] = -24; }
                else stack[sp++] = handle;
            } else if (id == 12 && argc == 1) {
                uint64_t pointer = (uint64_t)stack[--sp];
                char path[256];
                if (!read_string(memory, pointer, path, sizeof(path))) return fail("GWO2 VM unlink path fault");
                stack[sp++] = remove(path) == 0 ? 0 : -2;
            } else if (id == 13 && argc == 2) {
                uint64_t count = stack[--sp], pointer = (uint64_t)stack[--sp];
                if (!memory_span(pointer, count)) return fail("GWO2 VM print bytes bounds fault");
                fwrite(memory + pointer, 1, (size_t)count, stdout);
            } else if (id == 14 && argc == 0) {
                stack[sp++] = 0;
            } else {
                return fail("GWO2 VM unsupported import");
            }
            break;
        }
        case 20: { /* call(target, argc, result) */
            if (pc + 4 > image->code_size || fp + 1 >= VM_MAX_FRAMES)
                return fail("GWO2 VM call frame fault");
            uint32_t target = (uint32_t)image->code[pc] | (uint32_t)image->code[pc + 1] << 8;
            uint8_t argc = image->code[pc + 2], result = image->code[pc + 3];
            if (target >= image->code_size || argc > sp || result > 1)
                return fail("GWO2 VM call target/stack fault");
            vm_frame_t *frame = &frames[++fp];
            frame->return_pc = pc + 4;
            frame->base = sp - argc;
            frame->result = result;
            memset(frame->locals, 0, sizeof(frame->locals));
            for (uint8_t i = 0; i < argc; ++i) frame->locals[i] = stack[frame->base + i];
            pc = target;
            break;
        }
        case 13: /* return */
            if (sp == 0) return fail("GWO2 VM return stack fault");
            {
                int64_t value = stack[--sp];
                if (fp == 0) return (int)value;
                vm_frame_t frame = frames[fp--];
                sp = frame.base;
                if (frame.result) stack[sp++] = value;
                pc = frame.return_pc;
            }
            break;
        case 14: /* halt */
            return 0;
        case 21: /* return_void */
            if (fp == 0) return 0;
            {
                vm_frame_t frame = frames[fp--];
                sp = frame.base;
                pc = frame.return_pc;
            }
            break;
        default:
            return fail("GWO2 VM unknown opcode");
        }
    }
    if (steps >= limit) return fail("GWO2 VM instruction limit exceeded");
    return fail("GWO2 VM fell off bytecode");
}

int main(int argc, char **argv) {
    if (argc < 2 || argc > 3) {
        fprintf(stderr, "usage: grvm <program.gwo> [step-limit]\n");
        return 2;
    }
    uint64_t limit = argc == 3 ? strtoull(argv[2], NULL, 0) : 1000000u;
    char error[160];
    gwo2_image_t image;
    if (!gwo2_load(argv[1], &image, error, sizeof(error))) return fail(error);
    int status = run(&image, limit);
    gwo2_free(&image);
    return status;
}
