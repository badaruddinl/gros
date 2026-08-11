# Self-Hosting Alpha Evidence Boundary

This document separates what the current `development` revision actually
demonstrates from what the formal Self-Hosting Alpha 1 gate still has to prove.
The detailed atomic work plan is maintained in
`docs/41-self-hosting-alpha-roadmap.md`; this file is the evidence ledger, not a
second roadmap.

## Source identity

The release-candidate audit and local runtime campaign discussed here use:

```txt
branch: development
commit: 99f46f591b5a9fed779e3bf4093dd43bf736e032
subject: close external release audit blockers
```

The independent feedback audited the previous committed source, contracts, and
test harnesses. Its five release blockers were fixed in this commit: the
compiled `task_yield` artifact is now spawned and checked, the mutation lane
restores a clean contract and checks the specific void-result diagnostic, ATA
fault injection reaches the post-probe/read status path without overwriting
the failure code, and `grogan-clean-checkout` is a dependency of
`validate-release`. A script's presence is static evidence; a recorded
successful run is runtime evidence; neither may silently stand in for the
other.

## Remote CI activation

The repository's `GrOS Self-Hosting Alpha Release` workflow was manually
disabled in GitHub Actions during the first external audit. It has now been
re-enabled for `development`; the next documentation push is intentionally
used to create the immutable workflow run that must accompany this evidence
ledger. Until that run completes successfully, local gate results remain local
evidence rather than a GitHub release check.

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

The implementation session recorded successful runs on the exact commit above:

```bash
CYCLES=100 make grogan-resource-leaks-qemu
ATTEMPTS=96 make grogan-process-create-failures-qemu
make grogan-compiler-bounds-qemu grogan-ata-failures-qemu
make validate-static
make grogan-clean-checkout
make validate-release
```

The full static lane passed in 311 seconds, the full QEMU lane in 445 seconds,
and the aggregate `validate-release` target passed in 1,823 seconds. That
aggregate included the static lane, QEMU lane (448 seconds in the aggregate),
100 clean-boot reliability cycles, and two isolated clean-checkout builds.
The standalone reliability run also passed 100 cycles in 1,045 seconds. The
two clean QEMU boots reproduced the fixed-point hash
`fb040561c29ab0ef1f3c69972f5117202d11ae7c3d421c4a15b3a9b18e30dc56`.
These are recorded runtime results, not inferred from script presence.

The pre-modular parent image/kernel baseline recorded by
`scripts/check_grogan_longmode_modularity.sh` is:

```txt
image : 27db3326c0a7492e54ab82d108a440d38b39525106729212866d378d28cb48d9
kernel: ff251bfcec221cc80b9fbc20a1ee097a684f0930dcfb31ef215bc20230af094e
```

## Proven current capabilities

- The ring-3 shell provides `ls`, `cat`, `write`, `edit`, `grc`, `run`, `rm`,
  and `exit`, with persistent GFS2 source and artifact storage.
- Hosted and in-OS compilers support the Alpha Grown subset and one-level
  root-filename module imports.
- Corrupt-magic and unsupported-import GWO2 artifacts are rejected without a
  kernel stop.
- A boundary-spanning user buffer returns `-EFAULT` and leaves the kernel live.
- `mem_grow` exhaustion returns `-ENOMEM` to the process.
- A disk whose ATA-reported capacity ends before GFS2, reports `ERR`, or never
  raises `DRQ` is rejected with bounded `ATAFAIL` behavior.
- The ATA fault lane requires distinct `ATAERR`, `ATATMO`, and `ATARANGE`
  markers, proving the injected status, timeout, and range branches rather
  than a shared direct-failure shim.
- The in-OS compiler consumes the same generated boundary corpus as the host
  lane, including the void `task_yield()` import; its result flag is checked by
  ABI mutation tests and its runtime artifact is exercised under QEMU.
- Host GFS2 fixtures cover remount, mutation rejection, disk-full behavior,
  overwrite/truncate/append, and unlink.
- Two independent `git archive HEAD` compiler/image builds are byte-equal and
  ignore a poison untracked source in the caller worktree.
- Every injected `process_create` allocation edge returns the child object to
  the reusable state; the next spawn succeeds in the same boot.
- Every resource campaign snapshot records frame/handle counts and owner PID;
  all 100 spawn/wait/reap cycles return to the same baseline.
- The kernel is an ordered include driver over entry, process, memory, driver,
  filesystem, runtime, architecture, and data units; the modular output is
  byte-identical to the monolithic parent.

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

## Closed proof obligations found by the audit

| Obligation | Evidence | Roadmap work |
| --- | --- | --- |
| Reusable child after OOM | `qemu_grogan_process_create_failures.sh` covers all 74 owned-frame edges and verifies `PCA/PCF/PCS`, retry, and exit status. | P0-A, P1-A |
| `process_wait` result | TSV, Markdown, Grown contract, Rust/Grown lowering, and `WAITOK` zero/nonzero fixture agree on signed exit status. | P0-B |
| Identifier safety/parity | Host and in-OS 31/32/63/64 corpus plus guard mutation test. | P0-C |
| Literal encoding parity | Host and in-OS 255/256 corpus plus guard mutation test. | P0-D |
| Resource leak proof | `R<frames>H<handles>P<pid>` is compared per cycle for 100 cycles. | P1-B |
| ATA fault coverage | Separate ERR, timeout, and out-of-range QEMU images finish bounded and without `ATAOK`. | P1-C |
| Void import result parity | `task_yield` lowering is void in Rust, Grown, and the kernel VM; isolated mutation and QEMU lanes reject a synthetic `drop`, then spawn the compiled artifact and require `YIELDOK`. | P1-D |
| Shared compiler corpus | One generated fixture corpus drives host accept/reject checks and the in-OS process-spawn compiler lane. | P0-C, P0-D |
| ABI single source | Full TSV parser, generated NASM include, C/Rust/Grown/kernel parity, and column mutation lane. | P1-D |
| Clean-checkout reproducibility | Two isolated `git archive HEAD` builds and a poison untracked input produce equal manifests. | P1-E |
| Kernel maintainability | Thirteen ordered include units cover entry, arch, MM, proc, drivers, FS, runtime, and data with direct-parent byte identity. | P2-A |

The remaining release action is the fresh external chatgpt.com audit of this
commit and its GitHub Actions check/artifact. Native code generation and
general-purpose hardware support remain deliberately outside this Alpha
release.

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
