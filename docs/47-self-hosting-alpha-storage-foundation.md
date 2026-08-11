# Self-Hosting Alpha Storage Foundation

The first persistent disk path is now connected to the Grogan kernel.

## Implemented

- The long-mode image reserves a 128-block GFS2 volume at LBA 128, beyond the
  BIOS kernel transfer window. The image builder formats both superblock copies
  and checks the result before returning the artifact.
- The kernel probes the QEMU primary IDE device with IDENTIFY, records its
  LBA28 capacity, and exposes bounded one-block PIO reads and writes. Status
  polling has an explicit timeout and converts device errors to failure.
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
diagnostic fallback. The bounded Alpha profile is one root directory and one
512-byte regular-file extent per operation; multi-block files, crash-injected
recovery, and ring-3 editor utilities remain explicit follow-on work.
