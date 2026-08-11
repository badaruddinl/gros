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

## Evidence

```bash
make gfs2-host gfs2-host-failures
make grogan-storage
make grogan-storage-qemu
```

The boot trace contains `ATAOKGFS2OK` before the syscall/user transition.

## Still deliberately open

The kernel shell still reads the historical embedded GFS1 seed; GFS2 file
syscalls, metadata updates from ring 3, and crash-recoverable write ordering are
the next storage integration batches. The host GFS2 checker is the authority
for those metadata invariants until the syscall layer is connected.
