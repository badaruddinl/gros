#define _FILE_OFFSET_BITS 64
#define _POSIX_C_SOURCE 200809L
#include "gwo2.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint32_t get32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static void put32(uint8_t *p, uint32_t value) {
    for (unsigned i = 0; i < 4; ++i) p[i] = (uint8_t)(value >> (8u * i));
}

static int load_bytes(const char *path, uint8_t **bytes_out, size_t *size_out) {
    FILE *file = fopen(path, "rb");
    if (!file || fseeko(file, 0, SEEK_END) != 0) {
        if (file) fclose(file);
        return 0;
    }
    off_t length = ftello(file);
    if (length <= 0 || fseeko(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return 0;
    }
    uint8_t *bytes = (uint8_t *)malloc((size_t)length);
    if (!bytes || fread(bytes, 1, (size_t)length, file) != (size_t)length) {
        free(bytes);
        fclose(file);
        return 0;
    }
    fclose(file);
    *bytes_out = bytes;
    *size_out = (size_t)length;
    return 1;
}

static int save_bytes(const char *path, const uint8_t *bytes, size_t size) {
    FILE *file = fopen(path, "wb");
    int ok = file != NULL;
    if (ok && fwrite(bytes, 1, size, file) != size) ok = 0;
    if (file && fclose(file) != 0) ok = 0;
    return ok;
}

static int emit_base(const char *path, const char *kind) {
    static const uint8_t valid[] = {1, 1, 0, 0, 0, 14};
    static const uint8_t unknown[] = {0xff, 14};
    static const uint8_t underflow[] = {3, 0, 14};
    static const uint8_t nonboundary[] = {1, 1, 0, 0, 0, 10, 0xff, 0xff, 14};
    static const uint8_t import_bad[] = {12, 99, 0, 14};
    const uint8_t *code = valid;
    uint32_t size = (uint32_t)sizeof(valid);
    if (strcmp(kind, "unknown") == 0) { code = unknown; size = (uint32_t)sizeof(unknown); }
    else if (strcmp(kind, "underflow") == 0) { code = underflow; size = (uint32_t)sizeof(underflow); }
    else if (strcmp(kind, "nonboundary") == 0) { code = nonboundary; size = (uint32_t)sizeof(nonboundary); }
    else if (strcmp(kind, "import") == 0) { code = import_bad; size = (uint32_t)sizeof(import_bad); }
    char error[160];
    if (!gwo2_emit_bytecode(path, code, size, 0, error, sizeof(error))) {
        fprintf(stderr, "error: %s\n", error);
        return 0;
    }
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: gwo2_fixture <output.gwo> <kind>\n");
        return 2;
    }
    const char *path = argv[1];
    const char *kind = argv[2];
    if (strcmp(kind, "unknown") == 0 || strcmp(kind, "underflow") == 0 ||
        strcmp(kind, "nonboundary") == 0 || strcmp(kind, "import") == 0) {
        return emit_base(path, kind) ? 0 : 1;
    }
    if (strcmp(kind, "bad-magic") == 0 || strcmp(kind, "bad-checksum") == 0 ||
        strcmp(kind, "overlap") == 0 || strcmp(kind, "bad-size") == 0 ||
        strcmp(kind, "bad-entry") == 0) {
        if (!emit_base(path, "valid")) return 1;
        uint8_t *bytes = NULL;
        size_t size = 0;
        if (!load_bytes(path, &bytes, &size) || size < GWO2_HEADER_SIZE + GWO2_SECTION_SIZE) {
            free(bytes);
            return 1;
        }
        if (strcmp(kind, "bad-magic") == 0) bytes[0] = 0;
        else if (strcmp(kind, "bad-checksum") == 0) bytes[size - 1] ^= 0x5a;
        else if (strcmp(kind, "overlap") == 0) put32(bytes + GWO2_HEADER_SIZE + 4, GWO2_HEADER_SIZE);
        else if (strcmp(kind, "bad-size") == 0) put32(bytes + 24, get32(bytes + 24) + 1);
        else put32(bytes + 20, 1);
        if (strcmp(kind, "overlap") != 0 && strcmp(kind, "bad-magic") != 0 && strcmp(kind, "bad-checksum") != 0)
            put32(bytes + 28, gwo2_fnv1a(bytes + GWO2_HEADER_SIZE, size - GWO2_HEADER_SIZE));
        int ok = save_bytes(path, bytes, size);
        free(bytes);
        return ok ? 0 : 1;
    }
    fprintf(stderr, "error: unknown fixture kind '%s'\n", kind);
    return 2;
}
