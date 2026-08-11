# Self-Hosting Alpha Evidence Boundary

This document separates what the current `development` revision actually
demonstrates from what the formal Self-Hosting Alpha 1 gate still has to prove.
The detailed atomic work plan is maintained in
`docs/41-self-hosting-alpha-roadmap.md`; this file is the evidence ledger, not a
second roadmap.

## Source identity

The post-implementation audit and local runtime campaign discussed here use:

```txt
branch: development
commit: e7bb96e85e00631a6c53fdaf6fe339df07a9f585
subject: feat: close self-hosting alpha release gates
```

The independent feedback audited committed source, contracts, and test
harnesses. It did not itself execute QEMU for 100 cycles. A script's presence
is static evidence; a recorded successful run is runtime evidence; neither may
silently stand in for the other.

## Hosted fixed-point proof

Run from the repository root with the documented Rust and C host toolchains:

```bash
make gwo2-host gwo2-host-failures
make grogan-compiler grogan-compiler-failures
make grogan-self-host
```

`grogan-self-host` performs these real steps in a temporary directory:

1. compile `examples/grown-alpha/grc1.grw` with the Rust bootstrap
   `tools/grc0.rs` into a verified GWO2 compiler;
2. execute the Grown compiler with the host GrVM to produce the next compiler;
3. execute the generated compiler again on the same source; and
4. require byte equality between the canonical Grown-produced artifacts.

The Rust seed is a bootstrap input, not the artifact compared at the fixed
point. The C tools remain verifier/reference-VM oracles and are not a hidden C
compiler implementation.

## In-OS clean-room proof

```bash
make grogan-self-host-qemu
```

The image builder places the Rust-produced seed compiler and Grown source in
GFS2. The QEMU gate then uses the ring-3 shell to run:

```txt
grc grc1.grw grc2.gwo
run grc2.gwo grc1.grw grc3.gwo
```

It extracts the persisted artifacts, requires `grc2.gwo == grc3.gwo`, repeats
the whole operation on a second clean image, and requires the fixed-point hash
to match between clean boots. No host source path is consulted after either
boot begins.

## Recorded local release execution

The implementation session recorded a successful run of:

```bash
CYCLES=100 \
BOOT_WAIT=1 \
COMPILE_WAIT=4 \
SEND_DELAY=.005 \
QEMU_TIMEOUT=100 \
make validate-release
```

The run reported the static lane, complete QEMU lane, reproducibility gate,
and 100 clean-boot editor/compile/run/reboot cycles as successful. This proves
the functional behavior checked by the scripts at `e7bb96e`. It does not prove
an invariant the scripts do not measure.

## Proven current capabilities

- The ring-3 shell provides `ls`, `cat`, `write`, `edit`, `grc`, `run`, `rm`,
  and `exit`, with persistent GFS2 source and artifact storage.
- Hosted and in-OS compilers support the Alpha Grown subset and one-level
  root-filename module imports.
- Corrupt-magic and unsupported-import GWO2 artifacts are rejected without a
  kernel stop.
- A boundary-spanning user buffer returns `-EFAULT` and leaves the kernel live.
- `mem_grow` exhaustion returns `-ENOMEM` to the process.
- A disk whose ATA-reported capacity ends before GFS2 is rejected with bounded
  `ATAFAIL` behavior.
- Host GFS2 fixtures cover remount, mutation rejection, disk-full behavior,
  overwrite/truncate/append, and unlink.
- Two compiler/image builds from the same checkout are byte-equal and produce
  equal SHA-256 manifests.

Together these paths form a small computing environment rather than an
isolated kernel demonstration:

```txt
boot GrOS
  -> ring-3 shell
  -> edit and save source to GFS2
  -> compile source with the Grown compiler
  -> persist and spawn the resulting GWO2
  -> use the generated compiler on its own source
  -> reboot and repeat from persistent storage
```

The next proof question is no longer whether this workflow can happen; it is
whether every ownership, ABI, encoding, storage, and device invariant remains
true when an intermediate operation fails.

## Open proof obligations found by the audit

| Obligation | Current gap | Roadmap work |
| --- | --- | --- |
| Reusable child after OOM | Partial frame cleanup does not restore a canonical `PROC_EXITED` child object. | P0-A, P1-A |
| `process_wait` result | Kernel returns exit status; TSV/Markdown say PID. | P0-B |
| Identifier safety/parity | `grc1` can overrun a 32-byte name buffer; `grc0` accepts up to 63 bytes. | P0-C |
| Literal encoding parity | `grc1` can wrap a 256-byte string length into one GWO2 byte. | P0-D |
| Resource leak proof | The 100-cycle gate checks function and final GFS2 state, not frames/handles before and after each cycle. | P1-B |
| ATA fault coverage | Out-of-range is covered; forced device `ERR` and poll timeout are not. | P1-C |
| ABI single source | Selected rows are checked while syscall and import constants remain duplicated. | P1-D |
| Clean-checkout reproducibility | Both builds currently share one checkout and can see the same local tree. | P1-E |
| Kernel maintainability | `kernel/longmode_boot.asm` is a 5,933-line subsystem monolith. | P2-A |

Therefore `OOM process rollback complete`, `ATA failure campaign complete`,
`clean-checkout reproducible`, and `100 cycles with zero leaks` are not valid
claims yet. The narrower statements above are valid and remain regression
requirements while the missing obligations are implemented.

## Deliberate Alpha limits

- QEMU BIOS x86_64 is the only release target.
- GFS2 has one root directory, bounded filenames, one contiguous extent per
  regular file, and a 64 KiB file limit.
- GWO2 is a verified, bounded bytecode container; a native backend is deferred.
- The scheduler has two reusable process slots and one process-local handle.
- Grown modules are one-level root-file imports; recursive module graphs,
  arrays/records as richer language types, and richer structural typing are
  follow-on work.
- Crash-journal recovery, multiple directories, SMP, networking, USB, audio,
  GUI, UEFI, dynamic linking, POSIX compatibility, and package management are
  outside the Self-Hosting Alpha hardening boundary.

A formal `Self-Hosting Alpha 1` milestone is unlocked by the checklist in
`docs/41-self-hosting-alpha-roadmap.md`, not by static signatures, qualitative
ratings, or a gate name alone.
