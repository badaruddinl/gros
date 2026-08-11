#ifndef GROS_GWO2_H
#define GROS_GWO2_H

#include <stddef.h>
#include <stdint.h>

#define GWO2_VERSION 2u
#define GWO2_TARGET_GROGAN_X86_64 1u
#define GWO2_KIND_BYTECODE 1u
#define GWO2_HEADER_SIZE 32u
#define GWO2_SECTION_SIZE 16u
#define GWO2_MAX_SECTIONS 16u
#define GWO2_MAX_BYTES (1024u * 1024u)

typedef struct {
    uint8_t *bytes;
    size_t size;
    const uint8_t *code;
    uint32_t code_size;
    uint32_t entry_offset;
} gwo2_image_t;

uint32_t gwo2_fnv1a(const uint8_t *bytes, size_t size);
int gwo2_emit_bytecode(const char *path, const uint8_t *code, uint32_t code_size,
                       uint32_t entry_offset, char *error, size_t error_size);
int gwo2_load(const char *path, gwo2_image_t *image, char *error, size_t error_size);
int gwo2_verify(const gwo2_image_t *image, char *error, size_t error_size);
void gwo2_free(gwo2_image_t *image);

#endif
