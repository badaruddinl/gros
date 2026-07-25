# Boot-Resident Filesystem Seed

The long-mode image contains a small read-only filesystem block loaded with the
boot image: `GFS1`, one root entry named `INIT`, and payload `GRFS`. The
filesystem seed validates the superblock, looks up the root entry, allocates a
destination from the kernel heap, copies the payload, and verifies the copied
bytes before emitting `FSOK`.

This proves an image-resident storage-to-heap read boundary. It is not a block
driver, writable filesystem, directory tree, cache, pathname resolver, or
crash-safe on-disk format.
