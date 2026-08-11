# Self-Hosting Alpha GFS2 and Block Contract

This contract opens Batch 1.3. It is a small persistent filesystem for the
first self-hosting image, not a promise of POSIX or crash-proof journaling.

## Block device

The logical block size is 512 bytes. A device exposes:

```txt
capacity_blocks() -> u64
read(block: u64, count: u32, dst: *mut u8) -> Result
write(block: u64, count: u32, src: *const u8) -> Result
flush() -> Result
```

Requests outside capacity, with a zero count, or with an overflowing range are
rejected before touching the device. The first driver is ATA PIO LBA28 on the
QEMU primary IDE channel. Timeouts and device errors become `-EIO`; they never
loop forever with interrupts disabled.

## On-disk layout

Block zero is the primary superblock and block one is its recovery copy. The
superblock has little-endian fields:

```txt
magic              4 bytes: "GFS2"
version            u16: 2
block_size         u16: 512
sequence           u64: monotonically increasing committed metadata sequence
total_blocks       u64
bitmap_start       u64
bitmap_blocks      u32
inode_start        u64
inode_count        u32
root_inode         u32
metadata_checksum  u32
commit_marker      u32: 0x324d5443 ("CMT2")
```

The allocation bitmap, fixed inode table, and root directory follow the
superblock. An inode stores type, mode, size, extent count, and up to eight
bounded extents. A root directory entry stores a 31-byte UTF-8 name and an
inode number. Alpha supports one root directory; nested directories remain a
reserved extension.

The Alpha fixture uses deterministic table placement: blocks `0` and `1` are
the superblock pair, block `2` is the allocation bitmap, blocks `3..10` hold
32 fixed 128-byte inodes, and block `11` is the 512-byte root directory (eight
64-byte entries). File data starts at block `12`. Metadata checksums are
FNV-1a 32-bit over the bytes preceding each checksum field; a superblock is
mountable only when its checksum and `CMT2` commit marker are valid.

## Write ordering

The writer allocates data and metadata blocks, writes new data, writes the
inactive superblock copy with `sequence+1`, flushes, then writes the commit
marker and flushes again. Mount selects the highest sequence with a valid
checksum and commit marker. An interrupted write may lose the newest update,
but must not expose an extent overlap or an allocation bitmap disagreement.

## Alpha limits

```txt
filename <= 31 UTF-8 bytes
path <= 255 bytes
file size <= 8 MiB
open handles per process <= 64
extents per inode <= 8
```

## Batch 1.3 gate

Host fixtures must create, read, overwrite, truncate, append, unlink, remount,
and select the valid recovery superblock. Corrupt magic, sequence, checksum,
extent bounds, bitmap ownership, and directory names must be rejected without
modifying the image.

The host implementation and corruption fixtures are exercised by:

```bash
make gfs2-host gfs2-host-failures
```
