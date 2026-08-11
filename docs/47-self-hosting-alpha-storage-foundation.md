# Self-Hosting Alpha Storage Foundation

The first persistent disk path is now connected to the Grogan kernel.

## Implemented

- The long-mode image reserves a 192-block GFS2 volume at LBA 240, beyond the
  BIOS kernel transfer window. The image builder formats both superblock copies
  and checks the result before returning the artifact.
- The kernel probes the QEMU primary IDE device with IDENTIFY, prefers its
  validated LBA48 capacity with an LBA28 fallback, and exposes bounded
  one-block PIO reads and writes. Status polling has an explicit timeout and
  converts device errors to a bounded boot failure.
- Mount reads the primary and recovery superblocks, validates the GFS2 magic,
  version, bounds, FNV-1a checksum, and `CMT2` marker, then selects the highest
  valid sequence.
- Host fixtures implement the fixed inode table, bitmap, root directory,
  contiguous extents, create/overwrite/truncate/append/unlink, remount, and
  corruption rejection. The same on-disk bytes are used by the kernel mount.
- Kernel GFS2 operations now implement bounded root `create`, `open`, `read`,
  `write`, `stat`, `close`, and `unlink` paths with user-span checks,
  inode/bitmap/directory checksums, and inactive-superblock commits.
- The emergency shell's `save`, `ls`, and `cat` commands use GFS2, and the
  storage-smoke GWO2 program exercises the ring-3 file imports and unlink path.

## Evidence

```bash
make gfs2-host gfs2-host-failures
make grogan-storage
make grogan-storage-qemu
make grogan-storage-syscall-qemu
```

The boot trace contains `ATAOKGFS2OK` before the syscall/user transition. The
shell QEMU lane saves `hello.grw`, boots again, and reads the exact source;
the storage-smoke lane creates, writes, reads, closes, unlinks, and runs the
host checker against the resulting image.

## Still deliberately open

The kernel still retains the historical embedded GFS1 seed only as an emergency
diagnostic fallback. The bounded Alpha profile is one root directory with a
single contiguous extent per regular file (up to the documented 64 KiB limit).
Crash-injected journal recovery and multiple directories remain explicit
follow-on work; ring-3 editing and multi-block file I/O are covered by the
QEMU lanes.
