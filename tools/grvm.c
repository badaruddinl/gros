#define _POSIX_C_SOURCE 200809L
#include "gwo2.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint16_t get16(const uint8_t *p) { return (uint16_t)p[0] | (uint16_t)p[1] << 8; }
static int fail(const char *message) { fprintf(stderr, "error: %s\n", message); return 1; }

static int run(const gwo2_image_t *image, uint64_t limit) {
    int64_t stack[1024];
    int64_t locals[64] = {0};
    uint32_t sp = 0;
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
            stack[sp++] = locals[image->code[pc++]];
            break;
        }
        case 3: /* store_local */
            if (pc >= image->code_size || image->code[pc] >= 64 || sp == 0) return fail("GWO2 VM local store fault");
            locals[image->code[pc++]] = stack[--sp];
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
            } else {
                return fail("GWO2 VM unsupported import");
            }
            break;
        }
        case 13: /* return */
            return sp ? (int)stack[sp - 1] : 0;
        case 14: /* halt */
            return 0;
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
