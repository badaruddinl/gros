/*
 * GFS2 Alpha host image tool.
 *
 * The tool deliberately shares the byte-level layout used by the kernel
 * contract.  It is a bootstrap utility, not a POSIX filesystem adapter: one
 * root directory, fixed inodes, bounded names, and contiguous extents keep
 * the recovery rules deterministic while the ATA driver is still being
 * brought up.
 */
#define _FILE_OFFSET_BITS 64
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

#define BLOCK_SIZE 512u
#define SUPERBLOCKS 2u
#define BITMAP_BLOCK 2u
#define INODE_START 3u
#define INODE_COUNT 32u
#define INODE_SIZE 128u
#define INODE_BLOCKS 8u
#define ROOT_DIR_BLOCK 11u
#define MAX_EXTENTS 8u
#define MAX_FILENAME 31u
#define MAX_FILE_SIZE (8u * 1024u * 1024u)
#define COMMIT_MARKER 0x324d5443u /* CMT2 */

typedef struct {
    FILE *file;
    uint64_t base;
    uint32_t blocks;
} volume_t;

typedef struct {
    uint8_t bytes[BLOCK_SIZE];
    uint64_t sequence;
    uint64_t total_blocks;
    uint64_t bitmap_start;
    uint32_t bitmap_blocks;
    uint64_t inode_start;
    uint32_t inode_count;
    uint32_t root_inode;
    uint32_t checksum;
    uint32_t commit;
    unsigned valid;
} super_t;

typedef struct {
    uint8_t bytes[INODE_SIZE];
    uint16_t type;
    uint16_t mode;
    uint64_t size;
    uint32_t extent_count;
    uint64_t extent_start[MAX_EXTENTS];
    uint32_t extent_blocks[MAX_EXTENTS];
    unsigned valid;
} inode_t;

typedef struct {
    uint8_t bytes[64];
    uint8_t name_len;
    uint8_t flags;
    uint32_t inode;
    char name[MAX_FILENAME + 1];
    unsigned valid;
} dirent_t;

static void fail(const char *message) {
    fprintf(stderr, "error: %s\n", message);
    exit(1);
}

static void fail_errno(const char *message) {
    fprintf(stderr, "error: %s: %s\n", message, strerror(errno));
    exit(1);
}

static uint16_t get16(const uint8_t *p) {
    return (uint16_t)p[0] | (uint16_t)p[1] << 8;
}

static uint32_t get32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 |
           (uint32_t)p[3] << 24;
}

static uint64_t get64(const uint8_t *p) {
    uint64_t value = 0;
    for (unsigned i = 0; i < 8; ++i) value |= (uint64_t)p[i] << (8u * i);
    return value;
}

static void put16(uint8_t *p, uint16_t value) {
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
}

static void put32(uint8_t *p, uint32_t value) {
    for (unsigned i = 0; i < 4; ++i) p[i] = (uint8_t)(value >> (8u * i));
}

static void put64(uint8_t *p, uint64_t value) {
    for (unsigned i = 0; i < 8; ++i) p[i] = (uint8_t)(value >> (8u * i));
}

static uint32_t fnv1a(const uint8_t *bytes, size_t length) {
    uint32_t hash = 2166136261u;
    for (size_t i = 0; i < length; ++i) {
        hash ^= bytes[i];
        hash *= 16777619u;
    }
    return hash;
}

static int seek_block(const volume_t *volume, uint64_t block) {
    if (block >= volume->blocks) return 0;
    return fseeko(volume->file,
                  (off_t)(volume->base + block * (uint64_t)BLOCK_SIZE), SEEK_SET) == 0;
}

static int read_block(const volume_t *volume, uint64_t block, uint8_t bytes[BLOCK_SIZE]) {
    if (!seek_block(volume, block)) return 0;
    return fread(bytes, 1, BLOCK_SIZE, volume->file) == BLOCK_SIZE;
}

static int write_block(const volume_t *volume, uint64_t block, const uint8_t bytes[BLOCK_SIZE]) {
    if (!seek_block(volume, block)) return 0;
    if (fwrite(bytes, 1, BLOCK_SIZE, volume->file) != BLOCK_SIZE) return 0;
    return fflush(volume->file) == 0;
}

static void read_super(const volume_t *volume, uint32_t block, super_t *super) {
    memset(super, 0, sizeof(*super));
    if (!read_block(volume, block, super->bytes)) return;
    if (memcmp(super->bytes, "GFS2", 4) != 0) return;
    if (get16(super->bytes + 4) != 2 || get16(super->bytes + 6) != BLOCK_SIZE) return;
    super->sequence = get64(super->bytes + 8);
    super->total_blocks = get64(super->bytes + 16);
    super->bitmap_start = get64(super->bytes + 24);
    super->bitmap_blocks = get32(super->bytes + 32);
    super->inode_start = get64(super->bytes + 36);
    super->inode_count = get32(super->bytes + 44);
    super->root_inode = get32(super->bytes + 48);
    super->checksum = get32(super->bytes + 52);
    super->commit = get32(super->bytes + 56);
    if (super->commit != COMMIT_MARKER || super->checksum != fnv1a(super->bytes, 52)) return;
    if (super->total_blocks == 0 || super->total_blocks > volume->blocks) return;
    if (super->bitmap_start + super->bitmap_blocks > super->total_blocks) return;
    if (super->inode_start + INODE_BLOCKS > super->total_blocks) return;
    if (super->inode_count != INODE_COUNT || super->root_inode != 1) return;
    super->valid = 1;
}

static super_t choose_super(const volume_t *volume, unsigned *block) {
    super_t primary, recovery;
    read_super(volume, 0, &primary);
    read_super(volume, 1, &recovery);
    if (!primary.valid && !recovery.valid) fail("no valid GFS2 superblock");
    if (recovery.valid && (!primary.valid || recovery.sequence > primary.sequence)) {
        if (block) *block = 1;
        return recovery;
    }
    if (block) *block = 0;
    return primary;
}

static void make_super(uint8_t bytes[BLOCK_SIZE], uint64_t sequence, uint32_t total_blocks) {
    memset(bytes, 0, BLOCK_SIZE);
    memcpy(bytes, "GFS2", 4);
    put16(bytes + 4, 2);
    put16(bytes + 6, BLOCK_SIZE);
    put64(bytes + 8, sequence);
    put64(bytes + 16, total_blocks);
    put64(bytes + 24, BITMAP_BLOCK);
    put32(bytes + 32, 1);
    put64(bytes + 36, INODE_START);
    put32(bytes + 44, INODE_COUNT);
    put32(bytes + 48, 1);
    put32(bytes + 52, fnv1a(bytes, 52));
    put32(bytes + 56, COMMIT_MARKER);
}

static void read_inode(const volume_t *volume, const super_t *super, uint32_t number,
                       inode_t *inode) {
    memset(inode, 0, sizeof(*inode));
    if (number == 0 || number > super->inode_count) return;
    uint64_t offset = super->inode_start * BLOCK_SIZE + (uint64_t)(number - 1) * INODE_SIZE;
    uint32_t block = (uint32_t)(offset / BLOCK_SIZE);
    uint32_t within = (uint32_t)(offset % BLOCK_SIZE);
    uint8_t bytes[BLOCK_SIZE];
    if (within + INODE_SIZE <= BLOCK_SIZE) {
        if (!read_block(volume, block, bytes)) return;
        memcpy(inode->bytes, bytes + within, INODE_SIZE);
    } else {
        return;
    }
    if (memcmp(inode->bytes, "INO2", 4) != 0) return;
    if (get32(inode->bytes + 120) != fnv1a(inode->bytes, 120)) return;
    inode->type = get16(inode->bytes + 4);
    inode->mode = get16(inode->bytes + 6);
    inode->size = get64(inode->bytes + 8);
    inode->extent_count = get32(inode->bytes + 16);
    if (inode->extent_count > MAX_EXTENTS || inode->size > MAX_FILE_SIZE) return;
    for (unsigned i = 0; i < inode->extent_count; ++i) {
        inode->extent_start[i] = get64(inode->bytes + 24 + i * 12);
        inode->extent_blocks[i] = get32(inode->bytes + 32 + i * 12);
        if (inode->extent_blocks[i] == 0) return;
    }
    inode->valid = 1;
}

static void encode_inode(uint8_t bytes[INODE_SIZE], const inode_t *inode) {
    memset(bytes, 0, INODE_SIZE);
    if (!inode->valid) return;
    memcpy(bytes, "INO2", 4);
    put16(bytes + 4, inode->type);
    put16(bytes + 6, inode->mode);
    put64(bytes + 8, inode->size);
    put32(bytes + 16, inode->extent_count);
    for (unsigned i = 0; i < inode->extent_count; ++i) {
        put64(bytes + 24 + i * 12, inode->extent_start[i]);
        put32(bytes + 32 + i * 12, inode->extent_blocks[i]);
    }
    put32(bytes + 120, fnv1a(bytes, 120));
}

static void read_dirent(const uint8_t bytes[64], dirent_t *entry) {
    memset(entry, 0, sizeof(*entry));
    entry->name_len = bytes[0];
    entry->flags = bytes[1];
    entry->inode = get32(bytes + 2);
    if (entry->name_len == 0) return;
    if (entry->name_len > MAX_FILENAME || get32(bytes + 60) != fnv1a(bytes, 60)) return;
    memcpy(entry->name, bytes + 6, entry->name_len);
    entry->name[entry->name_len] = '\0';
    entry->valid = 1;
}

static void encode_dirent(uint8_t bytes[64], const dirent_t *entry) {
    memset(bytes, 0, 64);
    bytes[0] = entry->name_len;
    bytes[1] = entry->flags;
    put32(bytes + 2, entry->inode);
    memcpy(bytes + 6, entry->name, entry->name_len);
    put32(bytes + 60, fnv1a(bytes, 60));
}

static void read_directory(const volume_t *volume, dirent_t entries[8]) {
    uint8_t block[BLOCK_SIZE];
    if (!read_block(volume, ROOT_DIR_BLOCK, block)) fail("cannot read root directory");
    for (unsigned i = 0; i < 8; ++i) read_dirent(block + i * 64, &entries[i]);
}

static int bit_get(const uint8_t bitmap[BLOCK_SIZE], uint32_t block) {
    return (bitmap[block / 8] >> (block % 8)) & 1;
}

static void bit_set(uint8_t bitmap[BLOCK_SIZE], uint32_t block, int value) {
    uint8_t mask = (uint8_t)(1u << (block % 8));
    if (value) bitmap[block / 8] |= mask;
    else bitmap[block / 8] &= (uint8_t)~mask;
}

static void read_metadata(const volume_t *volume, const super_t *super,
                          uint8_t bitmap[BLOCK_SIZE], inode_t inodes[INODE_COUNT],
                          dirent_t entries[8]) {
    if (!read_block(volume, BITMAP_BLOCK, bitmap)) fail("cannot read GFS2 bitmap");
    for (uint32_t i = 0; i < INODE_COUNT; ++i) read_inode(volume, super, i + 1, &inodes[i]);
    read_directory(volume, entries);
}

static void write_all_inodes(const volume_t *volume, const inode_t inodes[INODE_COUNT]) {
    uint8_t block[BLOCK_SIZE];
    for (unsigned b = 0; b < INODE_BLOCKS; ++b) {
        memset(block, 0, sizeof(block));
        for (unsigned i = 0; i < 4; ++i) encode_inode(block + i * INODE_SIZE, &inodes[b * 4 + i]);
        if (!write_block(volume, INODE_START + b, block)) fail_errno("write inode table");
    }
}

static void write_directory(const volume_t *volume, const dirent_t entries[8]) {
    uint8_t block[BLOCK_SIZE];
    memset(block, 0, sizeof(block));
    for (unsigned i = 0; i < 8; ++i) {
        if (entries[i].valid) encode_dirent(block + i * 64, &entries[i]);
    }
    if (!write_block(volume, ROOT_DIR_BLOCK, block)) fail_errno("write root directory");
}

static void write_transaction(const volume_t *volume, const super_t *current,
                              const uint8_t bitmap[BLOCK_SIZE],
                              const inode_t inodes[INODE_COUNT], const dirent_t entries[8],
                              unsigned active_super) {
    if (!write_block(volume, BITMAP_BLOCK, bitmap)) fail_errno("write allocation bitmap");
    write_all_inodes(volume, inodes);
    write_directory(volume, entries);
    uint8_t bytes[BLOCK_SIZE];
    make_super(bytes, current->sequence + 1, (uint32_t)current->total_blocks);
    if (!write_block(volume, active_super ? 0 : 1, bytes)) fail_errno("commit GFS2 superblock");
}

static void open_volume(const char *path, uint64_t base, uint32_t blocks, const char *mode,
                        volume_t *volume) {
    volume->file = fopen(path, mode);
    if (!volume->file) fail_errno("open image");
    volume->base = base;
    volume->blocks = blocks;
}

static void close_volume(volume_t *volume) {
    if (fclose(volume->file) != 0) fail_errno("close image");
}

static void command_format(const char *path, uint64_t base, uint32_t blocks) {
    volume_t volume;
    open_volume(path, base, blocks, "r+b", &volume);
    uint8_t zero[BLOCK_SIZE] = {0};
    for (uint32_t i = 0; i < blocks; ++i) if (!write_block(&volume, i, zero)) fail_errno("zero GFS2 volume");
    uint8_t bitmap[BLOCK_SIZE] = {0};
    for (uint32_t i = 0; i <= ROOT_DIR_BLOCK; ++i) bit_set(bitmap, i, 1);
    if (!write_block(&volume, BITMAP_BLOCK, bitmap)) fail_errno("write initial bitmap");
    inode_t inodes[INODE_COUNT];
    memset(inodes, 0, sizeof(inodes));
    inodes[0].valid = 1;
    inodes[0].type = 2;
    inodes[0].mode = 0755;
    inodes[0].extent_count = 1;
    inodes[0].extent_start[0] = ROOT_DIR_BLOCK;
    inodes[0].extent_blocks[0] = 1;
    write_all_inodes(&volume, inodes);
    dirent_t entries[8];
    memset(entries, 0, sizeof(entries));
    write_directory(&volume, entries);
    uint8_t super[BLOCK_SIZE];
    make_super(super, 1, blocks);
    if (!write_block(&volume, 0, super) || !write_block(&volume, 1, super)) fail_errno("write GFS2 superblock");
    close_volume(&volume);
}

static uint32_t find_free_inode(const inode_t inodes[INODE_COUNT]) {
    for (uint32_t i = 1; i < INODE_COUNT; ++i) if (!inodes[i].valid) return i + 1;
    return 0;
}

static int find_entry(const dirent_t entries[8], const char *name) {
    for (unsigned i = 0; i < 8; ++i) if (entries[i].valid && strcmp(entries[i].name, name) == 0) return (int)i;
    return -1;
}

static void validate_root_name(const char *name) {
    size_t length = strlen(name);
    if (length == 0 || length > MAX_FILENAME) fail("filename exceeds GFS2 limit");
    for (size_t i = 0; i < length; ++i)
        if (name[i] == '/' || name[i] == '\\') fail("filename must stay in the GFS2 root directory");
}

static uint32_t allocate_extent(uint8_t bitmap[BLOCK_SIZE], uint32_t blocks, uint32_t need) {
    if (need == 0) return 0;
    for (uint32_t start = ROOT_DIR_BLOCK + 1; start + need <= blocks; ++start) {
        unsigned free = 1;
        for (uint32_t i = 0; i < need; ++i) if (bit_get(bitmap, start + i)) { free = 0; break; }
        if (!free) continue;
        for (uint32_t i = 0; i < need; ++i) bit_set(bitmap, start + i, 1);
        return start;
    }
    return 0;
}

static void free_inode_blocks(uint8_t bitmap[BLOCK_SIZE], inode_t *inode) {
    for (uint32_t i = 0; i < inode->extent_count; ++i)
        for (uint32_t b = 0; b < inode->extent_blocks[i]; ++b)
            bit_set(bitmap, (uint32_t)inode->extent_start[i] + b, 0);
    inode->extent_count = 0;
    inode->size = 0;
}

static void command_put(const char *path, uint64_t base, uint32_t blocks,
                        const char *name, const char *source, int append) {
    validate_root_name(name);
    size_t name_len = strlen(name);
    FILE *input = fopen(source, "rb");
    if (!input) fail_errno("open source");
    if (fseeko(input, 0, SEEK_END) != 0) fail_errno("seek source");
    off_t size = ftello(input);
    if (size < 0 || (uint64_t)size > MAX_FILE_SIZE) fail("source exceeds GFS2 file limit");
    if (fseeko(input, 0, SEEK_SET) != 0) fail_errno("rewind source");
    uint8_t *data = (uint8_t *)malloc((size_t)size ? (size_t)size : 1);
    if (!data || (size && fread(data, 1, (size_t)size, input) != (size_t)size)) fail_errno("read source");
    fclose(input);

    volume_t volume;
    open_volume(path, base, blocks, "r+b", &volume);
    unsigned active;
    super_t super = choose_super(&volume, &active);
    uint8_t bitmap[BLOCK_SIZE];
    inode_t inodes[INODE_COUNT];
    dirent_t entries[8];
    read_metadata(&volume, &super, bitmap, inodes, entries);
    int entry_index = find_entry(entries, name);
    uint32_t inode_number;
    if (entry_index >= 0) inode_number = entries[entry_index].inode;
    else {
        inode_number = find_free_inode(inodes);
        if (!inode_number) fail("GFS2 inode table full");
        for (unsigned i = 0; i < 8; ++i) if (!entries[i].valid) { entry_index = (int)i; break; }
        if (entry_index < 0) fail("GFS2 root directory full");
        memset(&entries[entry_index], 0, sizeof(entries[entry_index]));
        entries[entry_index].valid = 1;
        entries[entry_index].name_len = (uint8_t)name_len;
        entries[entry_index].inode = inode_number;
        memcpy(entries[entry_index].name, name, name_len + 1);
    }
    if (append) {
        if (entry_index < 0 || !inodes[inode_number - 1].valid || inodes[inode_number - 1].type != 1)
            fail("append target not found");
        inode_t *old_inode = &inodes[inode_number - 1];
        uint64_t old_size = old_inode->size;
        uint64_t total_size = old_size + (uint64_t)size;
        if (total_size > MAX_FILE_SIZE || total_size < old_size) fail("append exceeds GFS2 file limit");
        uint8_t *combined = (uint8_t *)malloc(total_size ? (size_t)total_size : 1);
        if (!combined) fail_errno("allocate append buffer");
        uint64_t copied = 0;
        uint8_t block[BLOCK_SIZE];
        for (uint32_t e = 0; e < old_inode->extent_count && copied < old_size; ++e) {
            for (uint32_t b = 0; b < old_inode->extent_blocks[e] && copied < old_size; ++b) {
                if (!read_block(&volume, old_inode->extent_start[e] + b, block)) fail("read append target");
                size_t take = old_size - copied > BLOCK_SIZE ? BLOCK_SIZE : (size_t)(old_size - copied);
                memcpy(combined + copied, block, take);
                copied += take;
            }
        }
        if (size) memcpy(combined + old_size, data, (size_t)size);
        free(data);
        data = combined;
        size = (off_t)total_size;
    }
    inode_t *inode = &inodes[inode_number - 1];
    if (inode->valid) free_inode_blocks(bitmap, inode);
    memset(inode, 0, sizeof(*inode));
    inode->valid = 1;
    inode->type = 1;
    inode->mode = 0644;
    inode->size = (uint64_t)size;
    uint32_t needed = (uint32_t)(((uint64_t)size + BLOCK_SIZE - 1) / BLOCK_SIZE);
    if (needed) {
        uint32_t start = allocate_extent(bitmap, (uint32_t)super.total_blocks, needed);
        if (!start) fail("GFS2 disk full or extent unavailable");
        inode->extent_count = 1;
        inode->extent_start[0] = start;
        inode->extent_blocks[0] = needed;
        uint8_t block[BLOCK_SIZE];
        for (uint32_t i = 0; i < needed; ++i) {
            memset(block, 0, sizeof(block));
            size_t remaining = (size_t)size - (size_t)i * BLOCK_SIZE;
            size_t take = remaining > BLOCK_SIZE ? BLOCK_SIZE : remaining;
            if (take) memcpy(block, data + (size_t)i * BLOCK_SIZE, take);
            if (!write_block(&volume, start + i, block)) fail_errno("write GFS2 data");
        }
    }
    write_transaction(&volume, &super, bitmap, inodes, entries, active);
    free(data);
    close_volume(&volume);
}

static void command_get(const char *path, uint64_t base, uint32_t blocks,
                        const char *name, const char *target) {
    volume_t volume;
    open_volume(path, base, blocks, "rb", &volume);
    super_t super = choose_super(&volume, NULL);
    uint8_t bitmap[BLOCK_SIZE];
    inode_t inodes[INODE_COUNT];
    dirent_t entries[8];
    read_metadata(&volume, &super, bitmap, inodes, entries);
    int index = find_entry(entries, name);
    if (index < 0) fail("file not found");
    inode_t *inode = &inodes[entries[index].inode - 1];
    if (!inode->valid || inode->type != 1) fail("not a regular file");
    FILE *output = fopen(target, "wb");
    if (!output) fail_errno("open destination");
    uint8_t block[BLOCK_SIZE];
    uint64_t remaining = inode->size;
    for (uint32_t i = 0; i < inode->extent_count && remaining; ++i) {
        for (uint32_t b = 0; b < inode->extent_blocks[i] && remaining; ++b) {
            if (!read_block(&volume, inode->extent_start[i] + b, block)) fail("read GFS2 data");
            size_t take = remaining > BLOCK_SIZE ? BLOCK_SIZE : (size_t)remaining;
            if (fwrite(block, 1, take, output) != take) fail_errno("write destination");
            remaining -= take;
        }
    }
    fclose(output);
    close_volume(&volume);
}

static void command_ls(const char *path, uint64_t base, uint32_t blocks) {
    volume_t volume;
    open_volume(path, base, blocks, "rb", &volume);
    super_t super = choose_super(&volume, NULL);
    uint8_t bitmap[BLOCK_SIZE];
    inode_t inodes[INODE_COUNT];
    dirent_t entries[8];
    read_metadata(&volume, &super, bitmap, inodes, entries);
    for (unsigned i = 0; i < 8; ++i)
        if (entries[i].valid) printf("%s\t%" PRIu64 "\n", entries[i].name, inodes[entries[i].inode - 1].size);
    close_volume(&volume);
}

static void command_unlink(const char *path, uint64_t base, uint32_t blocks, const char *name) {
    validate_root_name(name);
    volume_t volume;
    open_volume(path, base, blocks, "r+b", &volume);
    unsigned active;
    super_t super = choose_super(&volume, &active);
    uint8_t bitmap[BLOCK_SIZE];
    inode_t inodes[INODE_COUNT];
    dirent_t entries[8];
    read_metadata(&volume, &super, bitmap, inodes, entries);
    int index = find_entry(entries, name);
    if (index < 0) fail("file not found");
    uint32_t inode_number = entries[index].inode;
    free_inode_blocks(bitmap, &inodes[inode_number - 1]);
    memset(&inodes[inode_number - 1], 0, sizeof(inodes[inode_number - 1]));
    memset(&entries[index], 0, sizeof(entries[index]));
    write_transaction(&volume, &super, bitmap, inodes, entries, active);
    close_volume(&volume);
}

static void command_check(const char *path, uint64_t base, uint32_t blocks) {
    volume_t volume;
    open_volume(path, base, blocks, "rb", &volume);
    super_t super = choose_super(&volume, NULL);
    uint8_t bitmap[BLOCK_SIZE];
    inode_t inodes[INODE_COUNT];
    dirent_t entries[8];
    read_metadata(&volume, &super, bitmap, inodes, entries);
    uint8_t expected[BLOCK_SIZE] = {0};
    /* The root directory block is owned by the root inode; all other
       metadata blocks are reserved before extents are walked below. */
    for (uint32_t i = 0; i < ROOT_DIR_BLOCK; ++i) bit_set(expected, i, 1);
    for (uint32_t i = 0; i < INODE_COUNT; ++i) {
        inode_t *inode = &inodes[i];
        if (!inode->valid) continue;
        if (i == 0 && inode->type != 2) fail("root inode type invalid");
        uint64_t bytes = 0;
        for (uint32_t e = 0; e < inode->extent_count; ++e) {
            uint64_t first_data_block = i == 0 ? ROOT_DIR_BLOCK : ROOT_DIR_BLOCK + 1;
            if (inode->extent_start[e] < first_data_block ||
                inode->extent_start[e] + inode->extent_blocks[e] > super.total_blocks)
                fail("inode extent outside volume");
            for (uint32_t b = 0; b < inode->extent_blocks[e]; ++b) {
                uint32_t block = (uint32_t)inode->extent_start[e] + b;
                if (bit_get(expected, block)) fail("overlapping GFS2 extent");
                bit_set(expected, block, 1);
            }
            bytes += (uint64_t)inode->extent_blocks[e] * BLOCK_SIZE;
        }
        if (inode->type == 1 && inode->size > bytes) fail("inode size exceeds extents");
    }
    unsigned names[8] = {0};
    for (unsigned i = 0; i < 8; ++i) if (entries[i].valid) {
        if (entries[i].inode == 0 || entries[i].inode > INODE_COUNT || !inodes[entries[i].inode - 1].valid)
            fail("directory references invalid inode");
        for (unsigned j = 0; j < i; ++j)
            if (entries[j].valid && strcmp(entries[j].name, entries[i].name) == 0) fail("duplicate directory name");
        names[i] = 1;
    }
    for (uint32_t i = 0; i < super.total_blocks && i < BLOCK_SIZE * 8; ++i)
        if (bit_get(bitmap, i) != bit_get(expected, i)) fail("allocation bitmap disagreement");
    (void)names;
    close_volume(&volume);
    puts("gfs2: valid superblock, bitmap, inode extents, and root directory");
}

static uint64_t parse_u64(const char *text, const char *what) {
    char *end = NULL;
    errno = 0;
    unsigned long long value = strtoull(text, &end, 0);
    if (errno || !end || *end) {
        fprintf(stderr, "error: invalid %s: %s\n", what, text);
        exit(2);
    }
    return (uint64_t)value;
}

static void usage(void) {
    fprintf(stderr, "usage: gfs2 <format|check|put|append|get|ls|unlink> image offset blocks [name] [file]\n");
    exit(2);
}

int main(int argc, char **argv) {
    if (argc < 5) usage();
    const char *command = argv[1];
    const char *image = argv[2];
    uint64_t offset = parse_u64(argv[3], "offset");
    uint32_t blocks = (uint32_t)parse_u64(argv[4], "block count");
    if (blocks < ROOT_DIR_BLOCK + 2 || blocks > BLOCK_SIZE * 8) fail("unsupported GFS2 volume size");
    if (strcmp(command, "format") == 0 && argc == 5) command_format(image, offset, blocks);
    else if (strcmp(command, "check") == 0 && argc == 5) command_check(image, offset, blocks);
    else if (strcmp(command, "ls") == 0 && argc == 5) command_ls(image, offset, blocks);
    else if (strcmp(command, "put") == 0 && argc == 7) command_put(image, offset, blocks, argv[5], argv[6], 0);
    else if (strcmp(command, "append") == 0 && argc == 7) command_put(image, offset, blocks, argv[5], argv[6], 1);
    else if (strcmp(command, "get") == 0 && argc == 7) command_get(image, offset, blocks, argv[5], argv[6]);
    else if (strcmp(command, "unlink") == 0 && argc == 6) command_unlink(image, offset, blocks, argv[5]);
    else usage();
    return 0;
}
