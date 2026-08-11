#define _FILE_OFFSET_BITS 64
#define _POSIX_C_SOURCE 200809L
#include "gwo2.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint16_t get16(const uint8_t *p) { return (uint16_t)p[0] | (uint16_t)p[1] << 8; }
static uint32_t get32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}
static void put16(uint8_t *p, uint16_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
static void put32(uint8_t *p, uint32_t v) {
    for (unsigned i = 0; i < 4; ++i) p[i] = (uint8_t)(v >> (8u * i));
}

uint32_t gwo2_fnv1a(const uint8_t *bytes, size_t size) {
    uint32_t hash = 2166136261u;
    for (size_t i = 0; i < size; ++i) {
        hash ^= bytes[i];
        hash *= 16777619u;
    }
    return hash;
}

static void set_error(char *error, size_t size, const char *message) {
    if (error && size) {
        snprintf(error, size, "%s", message);
    }
}

static int read_file(const char *path, uint8_t **bytes_out, size_t *size_out,
                     char *error, size_t error_size) {
    FILE *file = fopen(path, "rb");
    if (!file) { set_error(error, error_size, "cannot open GWO2 file"); return 0; }
    if (fseeko(file, 0, SEEK_END) != 0) { fclose(file); set_error(error, error_size, "cannot seek GWO2 file"); return 0; }
    off_t length = ftello(file);
    if (length < (off_t)GWO2_HEADER_SIZE || length > (off_t)GWO2_MAX_BYTES) {
        fclose(file); set_error(error, error_size, "GWO2 size outside Alpha limit"); return 0;
    }
    if (fseeko(file, 0, SEEK_SET) != 0) { fclose(file); set_error(error, error_size, "cannot rewind GWO2 file"); return 0; }
    uint8_t *bytes = (uint8_t *)malloc((size_t)length);
    if (!bytes || fread(bytes, 1, (size_t)length, file) != (size_t)length) {
        free(bytes); fclose(file); set_error(error, error_size, "cannot read GWO2 file"); return 0;
    }
    fclose(file);
    *bytes_out = bytes;
    *size_out = (size_t)length;
    return 1;
}

int gwo2_load(const char *path, gwo2_image_t *image, char *error, size_t error_size) {
    memset(image, 0, sizeof(*image));
    if (!read_file(path, &image->bytes, &image->size, error, error_size)) return 0;
    if (!gwo2_verify(image, error, error_size)) { gwo2_free(image); return 0; }
    const uint8_t *section = image->bytes + GWO2_HEADER_SIZE;
    image->code = image->bytes + get32(section + 4);
    image->code_size = get32(section + 8);
    image->entry_offset = get32(image->bytes + 20);
    return 1;
}

int gwo2_emit_bytecode(const char *path, const uint8_t *code, uint32_t code_size,
                       uint32_t entry_offset, char *error, size_t error_size) {
    if (!code || code_size == 0 || code_size > GWO2_MAX_BYTES - GWO2_HEADER_SIZE - GWO2_SECTION_SIZE) {
        set_error(error, error_size, "bytecode size outside GWO2 limit"); return 0;
    }
    if (entry_offset >= code_size) { set_error(error, error_size, "GWO2 entry is outside bytecode"); return 0; }
    size_t size = GWO2_HEADER_SIZE + GWO2_SECTION_SIZE + code_size;
    uint8_t *bytes = (uint8_t *)calloc(1, size);
    if (!bytes) { set_error(error, error_size, "cannot allocate GWO2 image"); return 0; }
    memcpy(bytes, "GWO2", 4);
    put16(bytes + 4, GWO2_VERSION);
    put16(bytes + 6, GWO2_TARGET_GROGAN_X86_64);
    put16(bytes + 8, GWO2_KIND_BYTECODE);
    put16(bytes + 10, 0);
    put32(bytes + 12, GWO2_HEADER_SIZE);
    put32(bytes + 16, 1);
    put32(bytes + 20, entry_offset);
    put32(bytes + 24, code_size);
    memcpy(bytes + GWO2_HEADER_SIZE + GWO2_SECTION_SIZE, code, code_size);
    put32(bytes + GWO2_HEADER_SIZE, 1);
    put32(bytes + GWO2_HEADER_SIZE + 4, GWO2_HEADER_SIZE + GWO2_SECTION_SIZE);
    put32(bytes + GWO2_HEADER_SIZE + 8, code_size);
    put32(bytes + GWO2_HEADER_SIZE + 12, gwo2_fnv1a(code, code_size));
    put32(bytes + 28, gwo2_fnv1a(bytes + GWO2_HEADER_SIZE, GWO2_SECTION_SIZE + code_size));
    FILE *file = fopen(path, "wb");
    int ok = file != NULL;
    if (ok && fwrite(bytes, 1, size, file) != size) ok = 0;
    if (file && fclose(file) != 0) ok = 0;
    if (!ok) {
        free(bytes);
        set_error(error, error_size, "cannot write GWO2 image");
        return 0;
    }
    free(bytes);
    return 1;
}

static int boundary_contains(const uint8_t *boundaries, uint32_t size, uint32_t offset) {
    return offset < size && boundaries[offset];
}

int gwo2_verify(const gwo2_image_t *image, char *error, size_t error_size) {
    if (!image || !image->bytes || image->size < GWO2_HEADER_SIZE) { set_error(error, error_size, "empty GWO2 image"); return 0; }
    const uint8_t *h = image->bytes;
    if (memcmp(h, "GWO2", 4) != 0) { set_error(error, error_size, "GWO2 magic mismatch"); return 0; }
    if (get16(h + 4) != GWO2_VERSION || get16(h + 6) != GWO2_TARGET_GROGAN_X86_64) { set_error(error, error_size, "unsupported GWO2 version or target"); return 0; }
    if (get16(h + 8) != GWO2_KIND_BYTECODE) { set_error(error, error_size, "unsupported GWO2 executable kind"); return 0; }
    if (get32(h + 12) != GWO2_HEADER_SIZE || get32(h + 16) == 0 || get32(h + 16) > GWO2_MAX_SECTIONS) { set_error(error, error_size, "invalid GWO2 section table"); return 0; }
    uint32_t sections = get32(h + 16);
    uint64_t table_end = (uint64_t)GWO2_HEADER_SIZE + (uint64_t)sections * GWO2_SECTION_SIZE;
    if (table_end > image->size) { set_error(error, error_size, "GWO2 section table outside image"); return 0; }
    if (gwo2_fnv1a(h + GWO2_HEADER_SIZE, image->size - GWO2_HEADER_SIZE) != get32(h + 28)) { set_error(error, error_size, "GWO2 checksum mismatch"); return 0; }
    uint32_t code_offset = 0, code_size = 0;
    for (uint32_t i = 0; i < sections; ++i) {
        const uint8_t *s = h + GWO2_HEADER_SIZE + i * GWO2_SECTION_SIZE;
        uint32_t type = get32(s), offset = get32(s + 4), size = get32(s + 8), checksum = get32(s + 12);
        if (type != 1 || size == 0 || (uint64_t)offset + size > image->size || offset < table_end) { set_error(error, error_size, "invalid GWO2 bytecode section"); return 0; }
        if (gwo2_fnv1a(h + offset, size) != checksum) { set_error(error, error_size, "GWO2 section checksum mismatch"); return 0; }
        if (code_offset) { set_error(error, error_size, "multiple bytecode sections are not Alpha-safe"); return 0; }
        code_offset = offset; code_size = size;
    }
    uint32_t entry = get32(h + 20);
    if (get32(h + 24) != code_size || image->size != (size_t)(table_end + code_size)) {
        set_error(error, error_size, "GWO2 size fields do not match image");
        return 0;
    }
    if (entry >= code_size) { set_error(error, error_size, "GWO2 entry outside bytecode"); return 0; }
    uint8_t *boundaries = (uint8_t *)calloc(1, code_size);
    uint8_t *flow_kind = (uint8_t *)calloc(1, code_size);
    int32_t *flow_targets = (int32_t *)malloc((size_t)code_size * sizeof(*flow_targets));
    uint8_t *flow_argc = (uint8_t *)calloc(1, code_size);
    uint8_t *flow_result = (uint8_t *)calloc(1, code_size);
    if (!boundaries || !flow_kind || !flow_targets || !flow_argc || !flow_result) {
        free(flow_result); free(flow_argc); free(flow_targets); free(flow_kind); free(boundaries);
        set_error(error, error_size, "cannot allocate GWO2 verifier map");
        return 0;
    }
#define VERIFY_FREE() do { free(flow_result); free(flow_argc); free(flow_targets); free(flow_kind); free(boundaries); } while (0)
    uint32_t pc = 0;
    while (pc < code_size) {
        boundaries[pc] = 1;
        uint8_t op = h[code_offset + pc];
        uint32_t length = 1;
        if (op == 1) length = 5;
        else if (op == 2 || op == 3) {
            length = 2;
            if (pc + length <= code_size && h[code_offset + pc + 1] == 255) { VERIFY_FREE(); set_error(error, error_size, "GWO2 local index outside Alpha limit"); return 0; }
        }
        else if ((op >= 4 && op <= 9) || op == 22) length = 1;
        else if (op == 10 || op == 11) length = 3;
        else if (op == 12) length = 3;
        else if (op == 13 || op == 14 || op == 15 || op == 16 || op == 17 || op == 18 || op == 19 || op == 21) {
            if (op == 15) {
                if (pc + 2 > code_size) { VERIFY_FREE(); set_error(error, error_size, "invalid GWO2 byte constant boundary"); return 0; }
                length = 2u + h[code_offset + pc + 1];
            } else if (op == 16 || op == 17 || op == 18 || op == 19) length = 1;
        } else if (op == 20) length = 5;
        else { VERIFY_FREE(); set_error(error, error_size, "unknown GWO2 opcode"); return 0; }
        if (pc + length > code_size) { VERIFY_FREE(); set_error(error, error_size, "GWO2 instruction exceeds bytecode"); return 0; }
        if (op == 10 || op == 11) {
            int16_t delta = (int16_t)get16(h + code_offset + pc + 1);
            int64_t target = (int64_t)pc + length + delta;
            if (target < 0 || target >= code_size) { VERIFY_FREE(); set_error(error, error_size, "GWO2 jump outside bytecode"); return 0; }
            flow_kind[pc] = 1;
            flow_targets[pc] = (int32_t)target;
        } else if (op == 20) {
            uint16_t target = get16(h + code_offset + pc + 1);
            uint8_t argc = h[code_offset + pc + 3];
            uint8_t result = h[code_offset + pc + 4];
            if (target >= code_size || argc > 192 || result > 1) { VERIFY_FREE(); set_error(error, error_size, "invalid GWO2 call target or signature"); return 0; }
            flow_kind[pc] = 2;
            flow_targets[pc] = target;
            flow_argc[pc] = argc;
            flow_result[pc] = result;
        } else if (op == 12) {
            uint8_t import_id = h[code_offset + pc + 1];
            uint8_t argc = h[code_offset + pc + 2];
            int valid = ((import_id == 1 || import_id == 2) && argc == 1) ||
                        (import_id == 3 && argc == 0) ||
                        ((import_id == 4 || import_id == 5) && argc == 2) ||
                        ((import_id == 6 || import_id == 7) && argc == 3) ||
                        ((import_id == 8 || import_id == 11 || import_id == 12) && argc == 1) ||
                        (import_id == 9 && argc == 2) || (import_id == 10 && argc == 1) ||
                        (import_id == 13 && argc == 2) || (import_id == 14 && argc == 0) ||
                        (import_id == 15 && argc == 2) || (import_id == 16 && argc == 1);
            if (!valid) { VERIFY_FREE(); set_error(error, error_size, "unsupported GWO2 import signature"); return 0; }
        }
        pc += length;
    }
    if (!boundary_contains(boundaries, code_size, entry)) { VERIFY_FREE(); set_error(error, error_size, "GWO2 entry is not an instruction boundary"); return 0; }
    for (uint32_t offset = 0; offset < code_size; ++offset) {
        if (flow_kind[offset] && !boundary_contains(boundaries, code_size, (uint32_t)flow_targets[offset])) {
            VERIFY_FREE(); set_error(error, error_size, "GWO2 control-flow target is not an instruction boundary"); return 0;
        }
    }

    uint8_t *depths = (uint8_t *)malloc(code_size);
    if (!depths) { VERIFY_FREE(); set_error(error, error_size, "cannot allocate GWO2 stack map"); return 0; }
    memset(depths, 0xff, code_size);
    depths[entry] = 0;
    int changed = 1;
    while (changed) {
        changed = 0;
        for (pc = 0; pc < code_size; ) {
            if (depths[pc] == 0xff) {
                uint8_t op = h[code_offset + pc];
                if (op == 1) pc += 5;
                else if (op == 2 || op == 3) pc += 2;
                else if (op == 10 || op == 11 || op == 12) pc += 3;
                else if (op == 15) pc += 2u + h[code_offset + pc + 1];
                else if (op == 20) pc += 5;
                else pc += 1;
                continue;
            }
            uint8_t op = h[code_offset + pc];
            uint32_t length = op == 1 ? 5 : (op == 2 || op == 3 ? 2 :
                              (op == 10 || op == 11 || op == 12 ? 3 :
                              (op == 15 ? 2u + h[code_offset + pc + 1] : (op == 20 ? 5 : 1))));
            int effect = 0;
            unsigned need = 0;
            if (op == 1 || op == 2 || op == 15 || op == 18) effect = 1;
            else if (op == 3 || op == 19 || op == 13) { effect = -1; need = 1; }
            else if ((op >= 4 && op <= 9) || op == 22) { effect = -1; need = 2; }
            else if (op == 11) { effect = -1; need = 1; }
            else if (op == 16) { effect = -1; need = 2; }
            else if (op == 17) { effect = -3; need = 3; }
            else if (op == 12) {
                uint8_t id = h[code_offset + pc + 1], argc = h[code_offset + pc + 2];
                need = argc;
                if (id == 1 || id == 2 || id == 3) effect = -(int)argc;
                else if (id >= 4 && id <= 12) effect = 1 - (int)argc;
                else if (id == 13) effect = -(int)argc;
                else if (id == 14) effect = 1 - (int)argc;
            } else if (op == 20) {
                uint8_t argc = flow_argc[pc];
                need = argc;
                effect = (int)flow_result[pc] - (int)argc;
            }
            if (depths[pc] < need || (int)depths[pc] + effect < 0 || depths[pc] + effect > 192) {
                VERIFY_FREE(); free(depths); set_error(error, error_size, "GWO2 control-flow stack effect mismatch"); return 0;
            }
            uint8_t out = (uint8_t)((int)depths[pc] + effect);
            if (op == 20) {
                uint32_t target = (uint32_t)flow_targets[pc];
                uint8_t argc = flow_argc[pc];
                if (depths[target] == 0xff) { depths[target] = argc; changed = 1; }
                else if (depths[target] != argc) { VERIFY_FREE(); free(depths); set_error(error, error_size, "GWO2 call target stack signature mismatch"); return 0; }
            }
            int terminal = op == 10 || op == 13 || op == 14 || op == 21;
            if (!terminal && op != 11) {
                uint32_t next = pc + length;
                if (next >= code_size || !boundaries[next]) { VERIFY_FREE(); free(depths); set_error(error, error_size, "GWO2 fall-through is not an instruction boundary"); return 0; }
                if (depths[next] == 0xff) { depths[next] = out; changed = 1; }
                else if (depths[next] != out) { VERIFY_FREE(); free(depths); set_error(error, error_size, "GWO2 join stack depth mismatch"); return 0; }
            }
            if (op == 10 || op == 11) {
                uint32_t target = (uint32_t)flow_targets[pc];
                if (depths[target] == 0xff) { depths[target] = out; changed = 1; }
                else if (depths[target] != out) { VERIFY_FREE(); free(depths); set_error(error, error_size, "GWO2 jump stack depth mismatch"); return 0; }
            }
            pc += length;
        }
    }
    free(depths);
    VERIFY_FREE();
#undef VERIFY_FREE
    return 1;
}

void gwo2_free(gwo2_image_t *image) {
    if (!image) return;
    free(image->bytes);
    memset(image, 0, sizeof(*image));
}
