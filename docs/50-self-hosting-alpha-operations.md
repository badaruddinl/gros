# Self-Hosting Alpha Operations and Recovery

The Alpha image is a QEMU BIOS x86_64 development system. The supported
invocation is:

```bash
qemu-system-x86_64 \
  -drive format=raw,file=build/gros-longmode.img \
  -display none -monitor stdio -no-reboot -no-shutdown \
  -debugcon file:build/gros-debug.log \
  -global isa-debugcon.iobase=0xe9
```

After the `GrOS user shell` banner, the ring-3 commands are:

```txt
help
ls
cat <path>
write <path> <text>
edit <path>
grc <source.grw> <output.gwo>
run <artifact.gwo> [arg0 arg1]
rm <path>
exit
```

`edit` supports `insert`, `delete`, `save`, and `quit`. Saving an existing
file opens its inode and performs a checked replacement/truncate transaction;
the shell does not unlink the old directory entry before the write attempt.
The compiler and source files used by the fixed-point proof are already on
GFS2, so the host filesystem is not consulted after boot.

## Limits

- QEMU `x86_64` BIOS is the only release target; SMP, UEFI, networking, USB,
  audio, GUI, dynamic linking, POSIX compatibility, and native optimization are
  outside Alpha.
- The image uses a 192-block (98,304-byte) GFS2 volume beginning at LBA 240.
  It has one root directory and one contiguous extent per regular file, with a
  64 KiB file limit and bounded filenames.
- The loader accepts a verified GWO2 bytecode image up to four 4 KiB payload
  pages plus its header (16,432 bytes total). The VM has bounded stack/call
  depth and instruction budget; a trap exits only that process.
- The current scheduler has two reusable process slots and one process-local
  file handle. `process_spawn_args` carries at most 256 NUL-terminated bytes.
- Grown imports are root filenames (`import "module.grw";`) expanded one level
  at compile time. Imported files contain function declarations and share the
  importing program's target; nested imports are rejected by the in-OS compiler
  until a recursive module graph contract is added.
- Until P0 compiler-boundary hardening is complete, keep identifiers at no more
  than 31 bytes and byte-string literals at no more than 255 bytes. The Rust
  bootstrap already enforces the literal limit, but cross-compiler rejection
  parity for overlong identifiers and literals is still an explicit release
  obligation.
- User pointers are page-walked before every file/list operation; a buffer that
  crosses an unmapped page returns `-EFAULT` to the process. An ATA capacity
  below the filesystem LBA fails the boot with a bounded `ATAFAIL` marker.

## Filesystem recovery

Stop QEMU before inspecting an image. Always check a copy first:

```bash
cc -std=c11 -O2 -Wall -Wextra -Werror tools/gfs2.c -o /tmp/gfs2
/tmp/gfs2 check build/gros-longmode.img $((240 * 512)) 192
```

If the check rejects the image, preserve it for diagnosis and rebuild a clean
image with `scripts/build_longmode_image.sh`. The builder formats both GFS2
superblocks and seeds `grc1.gwo` plus `grc1.grw`; it never silently repairs a
corrupt image in place.

## Release evidence

```bash
make validate-static
make validate-qemu
make validate-self-host
make validate-release
```

`grogan-release` currently compares two compiler/image builds from the same
checkout and emits the same SHA-256 manifest. Two isolated `git archive HEAD`
builds remain the formal clean-checkout reproducibility requirement.
`grogan-reliability-qemu` runs 100 independent clean-boot
editor/compile/run/reboot cycles by default; set `CYCLES` lower only for local
iteration. It proves the functional markers it checks, but it does not yet
compare owned-frame and open-handle counters before and after every cycle.

The QEMU lane covers malformed/unsupported GWO2, cross-page user buffers, and
an out-of-range short-ATA-capacity failure. Validation-only device-`ERR` and ATA
poll-timeout injection remain open. Host fixtures mutate GFS2 superblocks,
bitmaps, extents, and disk-full states. The complete release-claim boundary and
atomic follow-up plan are in `docs/41-self-hosting-alpha-roadmap.md` and
`docs/50-self-hosting-alpha-evidence.md`.
