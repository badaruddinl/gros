# GrOS Self-Hosting Alpha Roadmap

This roadmap turns the bounded Grogan x86_64 Developer Preview into a minimal,
usable, self-hosting GrOS environment. It is a delivery plan, not a claim that
the listed capabilities already exist.

Every batch follows the repository transition rule:

```txt
contract -> validation -> implementation -> claim
```

## Target

Self-Hosting Alpha is complete when a clean GrOS image can:

1. boot the Grogan x86_64 profile under QEMU;
2. mount a writable persistent filesystem;
3. run `init`, a shell, and a small editor as isolated ring-3 processes;
4. read, write, and retain `.grw` source files across reboot;
5. compile a non-trivial Grown program inside GrOS;
6. load and execute the resulting `.gwo` artifact;
7. compile the Grown compiler's own source inside GrOS;
8. use that generated compiler to compile the same source again; and
9. produce the same canonical compiler artifact at the fixed point.

A compiler or user program fault must terminate only the responsible process.
It must not corrupt the filesystem or stop the kernel.

## Alpha Scope

The shortest sound route to self-hosting uses a typed Grown subset and a
deterministic bytecode virtual machine. A native optimizing backend is not
required for Alpha. The bytecode remains a real `.gwo` executable form and the
compiler remains self-hosting because it is implemented in Grown and compiles
its own Grown source.

The first supported machine remains QEMU `x86_64` with BIOS. Alpha does not
require SMP, networking, USB, audio, a GUI, UEFI, dynamic linking, POSIX
compatibility, package management, or an optimizing native backend.

## Stable Architecture Decisions

| Area | Alpha decision |
| --- | --- |
| Kernel | Grogan x86_64, monolithic, ring 0 |
| Userland | Ring 3 with one address space and kernel stack per process |
| Paging | 4 KiB user mappings; kernel bootstrap mapping remains supervisor-only |
| Storage | Block-device interface with QEMU IDE/ATA PIO as the first driver |
| Filesystem | GFS2, writable, single root directory, bounded filenames and files |
| Executable | Versioned GWO2 container with bytecode and future-native kinds |
| Runtime | Deterministic stack bytecode VM in a ring-3 runtime process |
| Language | Typed Grown subset with functions, locals, control flow, byte strings, and one-level modules |
| Bootstrap | Hosted `grc0`, then Grown `grc1`, then in-OS fixed-point rebuild |
| Console | Text console with blocking line input and byte-oriented output |

Changing one of these decisions requires updating its contract and negative
tests before implementation.

## Workstreams and Parallelism

After Phase 0, three workstreams may progress in parallel:

```txt
Kernel:     memory -> process -> syscall -> scheduler/fault isolation
Storage:    block API -> ATA -> GFS2 -> file syscalls and tools
Toolchain:  GWO2 -> VM -> grc0 -> Grown grc1 -> fixed point
```

Integration points prevent unsafe parallel work:

- Storage may implement and host-test GFS2 before process support, but it may
  not expose user file syscalls before user-pointer validation exists.
- Toolchain may implement GWO2, the VM, and hosted compiler tests before the
  kernel can run them, but in-OS execution waits for process and file APIs.
- Userland starts only after process loading, console syscalls, and the GWO2
  execution contract are stable.

## Phase 0 - Freeze the Developer Preview Baseline

### Batch 0.1 - Baseline identity

- Record the exact `development` commit used by the roadmap.
- Preserve `make validate-static`, `make validate-qemu`, and
  `make validate-release` as mandatory regression lanes.
- Keep generated build churn out of commits except the intentionally tracked
  `dist/` images.

Gate:

```bash
make validate-release
git diff --check
```

Exit condition: a clean checkout reproduces the committed image and passes all
existing Developer Preview proofs.

## Phase 1 - Contracts and Failure-First Validation

Phase 1 opens the closed implementation gates without prematurely claiming
general kernel, process, filesystem, or compiler support.

### Batch 1.1 - Process and address-space contract

- Specify process states: `new`, `ready`, `running`, `blocked`, `exited`.
- Specify the user virtual layout, guard pages, user stack, heap break, and
  kernel-only mappings.
- Specify TSS `RSP0`, per-process kernel stacks, syscall entry, and interrupt
  return behavior.
- Specify ownership of page tables, frames, handles, and exit status.

Required negative checks:

- user mappings may not carry supervisor kernel pages;
- an unmapped user pointer must be rejected;
- a user page fault must not enter the kernel fail-stop path; and
- a process may not free a frame owned by another process.

### Batch 1.2 - Syscall ABI v1 contract

Reserve selectors and exact register/error conventions for:

```txt
console_read  console_write
file_open     file_read      file_write     file_close     file_stat
mem_grow      process_spawn  process_wait   process_exit   task_yield
```

Define bounded path length, handle lifetime, partial reads/writes, blocking,
EOF, and negative error values. Define `copy_from_user` and `copy_to_user` as
the only permitted kernel access paths for caller buffers.

### Batch 1.3 - Block and GFS2 contract

- Define 512-byte logical blocks and a driver-neutral block API.
- Define the GFS2 superblock, allocation bitmap, fixed inode table, root
  directory entries, extents, and checksum fields.
- Define create, open, truncate, append, unlink, and reboot persistence.
- Provide a host-side image builder and checker before a writable kernel mount.

### Batch 1.4 - GWO2 and Grown Alpha contract

- Version the executable container independently from the language.
- Define GWO2 header, target, executable kind, section table, entry symbol,
  checksums, and maximum sizes.
- Define bytecode instruction encoding and verifier rules.
- Freeze the Grown Alpha grammar and type rules needed to implement its own
  compiler.

Exit condition: every new contract has a positive fixture, at least one
mutation-based negative test, and a Make target included in `validate-static`.

## Phase 2 - General Memory and Recoverable Faults

### Batch 2.1 - Physical-frame allocator

- Replace the 64-frame proof pool with an E820-backed page-frame database.
- Reserve firmware, kernel, image, page-table, DMA, and boot-info ranges.
- Implement allocate/free with ownership and double-free rejection.
- Add exhaustion and reuse tests.

### Batch 2.2 - 4 KiB paging manager

- Implement page-table creation, map, unmap, permission changes, and teardown.
- Support supervisor/user and read/write/no-execute policy where available.
- Add explicit TLB invalidation after mapping changes.
- Retain only the bootstrap identity mappings that the kernel still owns.

### Batch 2.3 - Kernel heap

- Build a multi-page heap over the frame and paging APIs.
- Support small allocations, alignment, free, coalescing or size classes, and
  deterministic out-of-memory errors.
- Add canaries or equivalent metadata validation for debug builds.

### Batch 2.4 - Exception classification

- Decode exception vector and error code.
- Recover from user page faults by terminating the process with diagnostics.
- Retain fail-stop behavior for kernel faults.
- Add QEMU proofs for user fault isolation and kernel fault fail-closed.

Exit condition: repeated allocation, mapping, process teardown, and user-fault
tests do not leak frames and do not corrupt kernel mappings.

## Phase 3 - Process, Syscall, and Scheduling Core

### Batch 3.1 - TSS and privilege transition

- Install a valid 64-bit TSS and load `TR`.
- Give every process a guarded kernel stack.
- Switch `RSP0` when scheduling a different process.
- Preserve the complete interrupt/syscall register context.

### Batch 3.2 - Process object and scheduler

- Replace the two hardcoded task contexts with an owned run queue.
- Implement PID allocation, parent/child relation, exit status, wait queue,
  blocking, wakeup, yield, and teardown.
- Schedule ring-3 processes preemptively with bounded kernel critical sections.

### Batch 3.3 - Safe syscall dispatcher

- Route selectors through one bounds-checked dispatcher table.
- Validate scalar ranges, handles, paths, and user memory spans.
- Make unsupported selectors return an error instead of stopping the kernel.
- Implement console I/O, `mem_grow`, `exit`, `yield`, and wait primitives first.

### Batch 3.4 - General GWO2 process loader

- Load a verified artifact from a kernel buffer into a fresh address space.
- Reject overlap, integer overflow, invalid entry points, invalid permissions,
  unsupported executable kinds, and bad checksums.
- Create argv/environment in a bounded initial user stack.

Exit condition: two independent ring-3 programs can run, block, exit, and be
reaped; a malformed program or pointer cannot modify kernel memory.

## Phase 4 - Persistent Storage

Host-side filesystem work from this phase may run in parallel with Phases 2
and 3. Kernel integration depends on their ownership and syscall contracts.

### Batch 4.1 - Block-device layer

- Add device registration and synchronous block read/write requests.
- Define timeout, retry, range, and short-transfer behavior.
- Provide an in-memory mock driver for deterministic tests.

### Batch 4.2 - ATA PIO driver

- Probe the primary QEMU IDE channel and identify the device.
- Implement LBA28 reads and writes with status polling and timeouts.
- Reject requests outside the identified capacity.
- Test injected timeout, device error, and out-of-range failures.

### Batch 4.3 - GFS2 read path

- Validate the superblock and all table bounds before mounting.
- Implement root lookup, stat, open, sequential/random read, and close.
- Reject corrupt inode, extent, bitmap, and directory metadata.

### Batch 4.4 - GFS2 write path

- Implement allocate, create, truncate, write, append, unlink, and flush.
- Update metadata in an order that is recoverable by `gfs2ck` after an
  interrupted write.
- Prevent cross-file extent overlap and allocation bitmap disagreement.

### Batch 4.5 - File syscall integration

- Add a per-process handle table with access modes and offsets.
- Connect the file syscalls exclusively through safe user-buffer copies.
- Release all handles during process teardown.

Exit condition: a source file created inside GrOS survives reboot, its checksum
matches, and corrupted test images fail to mount without modifying the disk.

## Phase 5 - Minimal Ring-3 Userland

### Batch 5.1 - Runtime and startup

- Define `_start`, argument access, syscall wrappers, process exit, and a small
  allocator for Grown programs.
- Keep the runtime freestanding and independent of a hosted C library.

### Batch 5.2 - `init` and shell

- Launch `/bin/init.gwo` as PID 1.
- Move the interactive shell out of the kernel.
- Implement command parsing, PATH lookup, spawn, wait, and exit reporting.

### Batch 5.3 - File utilities

Add bounded versions of:

```txt
ls  cat  write  cp  rm  stat  hexdump
```

### Batch 5.4 - Editor

- Implement a small line editor supporting open, insert, delete, save, and
  quit.
- Make failed saves preserve the previous file.
- Keep the source representation within documented Alpha memory limits.

Exit condition: all kernel-only shell commands used for daily work have ring-3
replacements and the kernel shell remains only an emergency diagnostic path.

## Phase 6 - GWO2 Bytecode Runtime

### Batch 6.1 - Bytecode verifier

- Validate instruction boundaries, jump targets, stack effects, local indexes,
  function signatures, constants, and entry point.
- Reject malformed bytecode before execution.

### Batch 6.2 - GrVM execution core

Implement the minimum instruction families:

```txt
constants and locals
integer and boolean operations
branches and loops
function call and return
byte arrays and indexed access
string/byte constants
runtime and syscall imports
```

### Batch 6.3 - Runtime safety

- Bounds-check VM stack, call depth, arrays, and memory growth.
- Return structured traps that terminate only the VM process.
- Add deterministic instruction-count limits for tests.

### Batch 6.4 - Host/kernel parity

- Provide a host reference runner for compiler tests.
- Run the same conformance artifacts in the host runner and GrOS runtime.
- Require matching stdout, exit status, and traps.

Exit condition: verified GWO2 bytecode executes identically on the host runner
and inside GrOS, including all negative fixtures.

## Phase 7 - Real Grown Compiler

### Batch 7.1 - Hosted bootstrap compiler `grc0`

Implement a real reference compiler, not normalized-source matching:

- lexer with source spans and comments;
- recursive-descent or Pratt parser;
- AST and symbol tables;
- name resolution and duplicate detection;
- type checking and definite returns;
- deterministic GWO2 bytecode emission; and
- stable diagnostics with file, line, and column.

### Batch 7.2 - Grown Alpha language surface

The minimum self-hosting subset includes:

```txt
modules and imports
functions and explicit types
local variables and assignment
if/else and while
integers, booleans, bytes, strings, and byte arrays
struct-like records or parallel arrays
file and console standard-library calls
```

Features not required by the compiler remain out of Alpha.

### Batch 7.3 - Compiler test corpus

- Golden lexer/parser/type/codegen tests.
- Negative diagnostics for every grammar and type rule.
- Multi-module compilation.
- Deterministic artifact test across clean builds.
- End-to-end programs larger than the compiler's individual modules.

### Batch 7.4 - Grown compiler `grc1`

- Reimplement lexer, parser, type checker, and emitter in the supported Grown
  subset.
- Keep `grc0` only as the bootstrap oracle.
- Compile `grc1` with `grc0` and execute it on the host GrVM first.

Exit condition: hosted `grc1` compiles all Alpha conformance programs and its
results match `grc0` semantically and byte-for-byte where canonicalization
requires it.

## Phase 8 - In-OS Compilation

### Batch 8.1 - Install compiler toolchain

- Package GrVM, `grc1.gwo`, standard modules, and compiler source in GFS2.
- Boot without reading compiler files from the host after image creation.

### Batch 8.2 - Compile and run inside GrOS

From the ring-3 shell:

```txt
edit hello.grw
grc hello.grw -o hello.gwo
hello.gwo
```

Validate syntax errors, type errors, missing files, disk-full, and out-of-memory
paths without kernel failure.

### Batch 8.3 - Multi-module and persistence proof

- Compile a program importing at least two source modules.
- Reboot and execute the persisted artifact without rebuilding it on the host.
- Compare source and artifact checksums before and after reboot.

Exit condition: day-to-day Grown edit/compile/run work happens entirely inside
GrOS after boot.

## Phase 9 - Self-Hosting Fixed Point

### Batch 9.1 - First in-OS compiler rebuild

- Run the installed `grc1` inside GrOS.
- Compile the complete compiler source into `grc2.gwo`.
- Record source manifest, compiler identity, options, and artifact checksum.

### Batch 9.2 - Fixed-point rebuild

- Run `grc2.gwo` inside GrOS.
- Compile the same source and options into `grc3.gwo`.
- Require canonical byte equality between `grc2.gwo` and `grc3.gwo`.

### Batch 9.3 - Clean-room proof

- Create a fresh filesystem image containing only the bootstrap inputs.
- Repeat the entire in-OS rebuild from a clean boot.
- Ensure no host path or generated host artifact is consulted at runtime.

Exit condition:

```txt
sha256(grc2.gwo) == sha256(grc3.gwo)
```

The equality must be reproduced on two clean runs.

## Phase 10 - Self-Hosting Alpha Release Gate

### Batch 10.1 - Reliability

- Run at least 100 automated boot/edit/compile/run/reboot cycles.
- Stress frame allocation, process creation, file creation, disk-full handling,
  and compiler memory growth.
- Verify zero leaked process-owned frames and handles after every cycle.

### Batch 10.2 - Negative and corruption suite

- Fuzz or mutate GWO2 headers and bytecode.
- Mutate GFS2 metadata and allocation maps.
- Exercise invalid syscalls and boundary-spanning user buffers.
- Inject ATA timeout and error statuses.

### Batch 10.3 - Reproducible distribution

- Rebuild the boot and disk images from a clean checkout twice.
- Require identical tracked artifacts and a clean Git worktree.
- Publish an artifact manifest and exact QEMU invocation.

### Batch 10.4 - Documentation and recovery

- Document boot, editing, compiling, running, filesystem checking, and image
  recovery.
- List all Alpha resource limits and unsupported hardware explicitly.

Release gate:

```bash
make validate-static
make validate-qemu
make validate-self-host
make validate-release
git diff --exit-code
```

## Delivery Rules Per Batch

Every batch is independently reviewable and must contain:

1. one contract or a referenced stable contract;
2. positive tests for the new path;
3. negative tests that fail when the implementation is deliberately damaged;
4. implementation no broader than the contract;
5. integration into the correct validation lane;
6. documentation that distinguishes implemented behavior from reserved work;
7. no unrelated generated files; and
8. a handoff recording commands, durations, limitations, and the next dependency.

Commit ordering inside a batch should be:

```txt
docs(contract) -> test(failing gate) -> feat/fix(implementation) -> docs(claim)
```

## Integration Checkpoints

| Checkpoint | Required completed batches | Demonstration |
| --- | --- | --- |
| C1 Safe user process | 1.*, 2.*, 3.* | Two isolated ring-3 processes and recoverable user fault |
| C2 Persistent workspace | 4.*, 5.1-5.4 | Edit/save/reboot/read from ring-3 shell |
| C3 Executable language | 6.*, 7.1-7.3 | Real Grown programs compile and run on host and GrOS |
| C4 In-OS development | 7.4, 8.* | Edit/compile/run entirely inside GrOS |
| C5 Self-host fixed point | 9.* | `grc2.gwo` equals `grc3.gwo` |
| C6 Alpha release | 10.* | Reproducible distribution passes reliability gate |

No checkpoint may be claimed from static signatures alone; its runtime
demonstration must be part of the QEMU validation lane.

## Initial Execution Order

The first implementation branch should execute these batches in order:

```txt
0.1
1.1 -> 1.2 -> 1.3 -> 1.4
2.1 -> 2.2 -> 2.4
3.1 -> 3.2 -> 3.3 -> 3.4
```

In parallel after `1.3` and `1.4` stabilize:

```txt
Storage:   4.1 -> 4.2 -> 4.3
Toolchain: 6.1 -> 6.2 and 7.1 -> 7.2
```

The first concrete implementation milestone is C1, not the compiler. A real
compiler cannot safely self-host until GrOS can allocate memory, validate user
pointers, isolate faults, load a process, and reclaim its resources.

## Current implementation checkpoint (`development` at `e7bb96e`)

The following roadmap work is now implemented and covered by executable gates:

| Area | Evidence | Status |
| --- | --- | --- |
| GWO2 v2 verifier and GrVM parity | `make gwo2-host gwo2-host-failures` | complete |
| Rust bootstrap compiler | `scripts/grc0.sh` (`tools/grc0.rs`) | complete |
| Grown compiler subset (`grc1.grw`) | `make grogan-compiler grogan-compiler-failures` | complete |
| Hosted compiler fixed point | `make grogan-self-host` | complete |
| Ring-3 GWO2 execution and GFS2 syscalls | `make grogan-processes grogan-storage` and their QEMU gates | complete |
| In-OS compile/run and persistence | `make grogan-self-host-qemu` | complete |
| General ring-3 shell, editor, argv, and listing | `make grogan-general-shell-qemu` | complete |
| One-level multi-module compile and execution | `make grogan-modules-qemu grogan-compiler-failures` | complete |
| Transactional process-allocation cleanup and malformed-artifact isolation | `make grogan-oom-qemu grogan-corruption-qemu grogan-process-create-failures-qemu` | complete; every owned allocation edge is injected and retried |
| Host disk-full and image mutation | `make gfs2-host-failures grogan-release-failures` | complete for the current fixtures |
| Committed-HEAD reproducible compiler/image builds | `make grogan-release grogan-clean-checkout` | complete; two independent `git archive HEAD` builds and poison fixture agree |
| Repeated clean-boot development cycles | `CYCLES=100 make grogan-reliability-qemu grogan-resource-leaks-qemu` | complete; every cycle returns frame/handle counters to baseline |
| ATA capacity, device `ERR`, and timeout rejection | `make grogan-ata-failures-qemu` | complete; three independent bounded-failure boots |

The hosted fixed-point proof compares the output produced by `grc1.gwo` with
the next output produced by that Grown compiler; it does not incorrectly
compare the Rust bootstrap seed with the canonical Grown output. The C host
verifier/VM is retained only as a reference oracle. `make validate-self-host`
is the short gate for both hosted and in-OS proofs. The current
`validate-release` target runs the static/QEMU lanes and the 100-cycle
functional campaign, but the post-commit audit below is the authoritative
boundary for a formal Self-Hosting Alpha 1 claim. Crash-journal recovery and
multi-directory GFS2 remain deliberately outside Alpha scope.

## Post-`e7bb96e` audit boundary

An external audit of committed source, contracts, and validation harnesses
classifies GrOS as a credible self-hosting research OS and a Self-Hosting Alpha
candidate, not as a general-purpose OS. The auditor did not execute the local
100-cycle QEMU campaign; repository runtime evidence and static audit evidence
must therefore remain separate claims.

The qualitative audit snapshot is retained for planning context, not used as a
release score:

| Area | Audit assessment | Boundary that matters for delivery |
| --- | ---: | --- |
| Project seriousness | 9.3/10 | An in-OS development environment now exists. |
| Self-hosting proof | 9.2/10 | `grc2 == grc3` is reproduced on two clean boots. |
| Validation engineering | 9.0/10 | OOM, corruption, pointer boundary, module, ATA-range, reproducibility, and reliability fixtures exist. |
| Compiler maturity | 6.5/10 | One-level modules work, but identifier and literal bounds are not yet parity-safe. |
| Kernel reliability | 6.8/10 | Frame cleanup improved, but failed child creation may poison the reusable slot. |
| Userland usefulness | 6.5/10 | Shell, editor, compile/run, listing, file read/write, and removal are usable. |
| Maintainability | 4.5/10 | `kernel/longmode_boot.asm` is 5,933 lines and owns too many subsystems. |
| Hardware portability | 2.5/10 | QEMU BIOS x86_64 remains the intentional Alpha target. |
| General-purpose OS | 3.5/10 | General-purpose support is not an Alpha acceptance criterion. |

### Audit reconciliation: implemented versus still unproven

| Audit item | Current evidence | Honest status |
| --- | --- | --- |
| Syscall selector drift (`0x09/0x0a` versus `0x0f/0x10`) | Contract and implementation now use `0x0f/0x10`. | closed |
| `process_create` allocation failure | `qemu_grogan_process_create_failures.sh` injects all 74 owned-frame edges, checks `PCA/PCF/PCS`, and retries each child slot. | closed |
| OOM and recoverable faults | QEMU covers `mem_grow -> -ENOMEM`, corrupt GWO2, and cross-page `-EFAULT`. | useful coverage; not exhaustive process-create fault injection |
| 100-cycle campaign | `qemu_grogan_resource_leaks.sh` records `R<frames>H<handles>P<pid>` for every spawn/wait/reap cycle. | closed; per-cycle frame/handle baseline is measured |
| Multi-module compiler | One-level root-file imports compile on host and inside GrOS. | complete for the Alpha module boundary |
| Compiler identifier bounds | Host and in-OS corpus covers 31/32/63/64; mutation lane proves removal of the Grown guard is caught. | closed at `IDENT_MAX=31` |
| String literal bounds | Host and in-OS corpus covers 255/256; mutation lane proves removal of the Grown guard is caught. | closed at `STRING_MAX=255` |
| ATA failure campaign | Three QEMU images force capacity range, device `ERR`, and bounded timeout branches. | closed |
| Reproducible distribution | `check_grogan_clean_checkout.sh` builds two archives and ignores a poison untracked input. | closed |
| ABI source of truth | Full TSV parser, generated NASM constants, Rust/Grown/C dispatch checks, and mutation lane. | closed |
| Kernel source structure | `kernel/longmode_boot.asm` is an ordered include driver over 13 subsystem units; the direct-parent image comparison is byte-identical. | closed for Alpha |
| Native Grown backend | GWO2 bytecode self-hosting is real and sufficient for Alpha. | deliberately deferred until Alpha is locked |

The corrected Phase 10 rule is: a gate name or script default is not enough.
Every invariant named by the roadmap must be measured by that gate.

## Smallest executable hardening plan

Each checkbox below is intentionally one reviewable action. Do not combine two
IDs merely because they touch the same source file. Every implementation ID
must first have a failing test or contract change, and its claim may be updated
only after the named gate passes.

### P0-A - Restore the reusable child slot after failed creation

Risk: `process_create` clears the process object before allocation. A partial
failure reclaims frames but leaves `PROC_STATE=0`, so the next spawn can return
`-EBUSY` until reboot.

- [x] **P0-A01 Contract:** state that every failed unpublished child creation
  leaves the child slot in one canonical reusable state.
- [x] **P0-A02 Reproducer:** add one validation-only allocation failure point
  inside `process_create` and prove `spawn -> -ENOMEM; spawn -> -EBUSY` on the
  current code without rebooting.
- [x] **P0-A03 Object reset:** after partial frame cleanup, clear stale links,
  arguments, handles, offsets, frame pointers, and exit data; set the canonical
  PID/state fields defined by P0-A01.
- [x] **P0-A04 Retry proof:** disable the injected failure and require the very
  next spawn in the same boot to succeed and exit normally.
- [x] **P0-A05 Regression lane:** add the reproducer to process negative tests
  and QEMU validation without weakening the existing `mem_grow` OOM test.

Exit condition: one forced `process_create` failure cannot turn the reusable
child slot into a permanent `-EBUSY` result.

### P0-B - Freeze the real `process_wait` result contract

The kernel returns the child's exit status, while the TSV and ABI document say
that `process_wait(pid)` returns the PID. Exit status is the chosen behavior.

- [x] **P0-B01 Contract:** change the machine-readable result to
  `exit-status-or-errno`.
- [x] **P0-B02 Documentation:** define success as the signed child exit status,
  `-EAGAIN` as not exited, and `-EINVAL` as an unsupported PID.
- [x] **P0-B03 Zero-status fixture:** spawn a child that exits `0` and require
  `process_wait` to return `0`.
- [x] **P0-B04 Nonzero-status fixture:** spawn a child that exits a nonzero
  sentinel and require the same sentinel.
- [x] **P0-B05 Negative fixture:** retain explicit invalid-PID and not-yet-exited
  checks.
- [x] **P0-B06 Parity gate:** make the full contract checker reject the old
  `pid-or-errno` wording.

Exit condition: kernel, TSV, Markdown ABI, runtime import documentation, and
positive/negative tests agree on exit-status semantics.

### P0-C - Bound identifiers identically in `grc0` and `grc1`

Alpha chooses `IDENT_MAX=31`, matching a 32-byte NUL-terminated compiler name
buffer. Increasing the internal structure to 64 bytes is not part of this fix.

- [x] **P0-C01 Contract:** record `IDENT_MAX=31` and require rejection before
  any destination write beyond byte 31.
- [x] **P0-C02 Rust boundary:** make `grc0` accept 31 bytes and reject 32 or
  more with the canonical diagnostic.
- [x] **P0-C03 Grown boundary:** make `grc1.read_ident` stop safely, consume or
  diagnose the overlong token deterministically, and keep the destination
  NUL-terminated.
- [x] **P0-C04 Corpus 31:** require a 31-byte identifier to compile with
  `grc0`, host-GrVM `grc1`, and in-GrOS `grc1`.
- [x] **P0-C05 Corpus 32:** require all three paths to reject 32 bytes.
- [x] **P0-C06 Corpus 63/64:** require all three paths to reject both historical
  edge cases without producing an artifact.
- [x] **P0-C07 Damage test:** deliberately remove the Grown bound and require
  the compiler failure lane to catch it.

Exit condition: the same identifier corpus has the same accept/reject result on
the Rust bootstrap, hosted Grown compiler, and in-OS Grown compiler.

### P0-D - Bound byte-string literals identically

GWO2 `const_bytes` has a one-byte length. Alpha accepts 255 payload bytes and
must reject 256 before emitting an opcode, length, or payload prefix.

- [x] **P0-D01 Contract:** state `STRING_MAX=255` for every string-producing
  source form.
- [x] **P0-D02 Grown guard:** reject a 256-byte literal in `grc1` before
  `emit8(state, index)` can wrap.
- [x] **P0-D03 Corpus 255:** require success through `grc0`, host-GrVM `grc1`,
  and in-GrOS `grc1`.
- [x] **P0-D04 Corpus 256:** require deterministic rejection through all three
  paths and no partial output artifact.
- [x] **P0-D05 Call-form coverage:** exercise both a primary byte string and
  the `print_str` lowering path.
- [x] **P0-D06 Damage test:** make the failure lane detect removal of the
  Grown guard.

Exit condition: no compiler can encode a wrapped `const_bytes` length.

### P1-A - Exhaust every `process_create` allocation failure edge

- [x] **P1-A01 Hook contract:** define a validation-only allocation countdown;
  production images must compile with the hook absent.
- [x] **P1-A02 Site inventory:** count every owned-frame allocation reachable
  from `process_create`, including page-table and mapped user/runtime pages.
- [x] **P1-A03 Failure loop:** for failure index `1..N`, require `-ENOMEM`, no
  kernel stop, and the canonical reusable child state.
- [x] **P1-A04 Frame baseline:** after every injected failure, require the
  process-owned frame count to equal its pre-spawn baseline.
- [x] **P1-A05 Retry loop:** after every injected failure, disable injection and
  require a successful spawn/wait in the same boot.
- [x] **P1-A06 End sentinel:** failure index `N+1` must not fire, proving the
  loop covered all allocation sites rather than stopping early.
- [x] **P1-A07 Release exclusion:** a static/negative test must prove that the
  distributed image cannot enable the injection hook.

Exit condition: process creation is transactionally correct at every allocation
edge, not only under `mem_grow` exhaustion.

### P1-B - Measure zero frame and handle leaks per reliability cycle

- [x] **P1-B01 Counter definition:** specify exactly which frame owners and
  process-local handles are counted and what the idle baseline is.
- [x] **P1-B02 Test marker:** add a validation-only, machine-parseable snapshot
  such as `RESOURCE frames=<n> handles=<n>`; do not add a production syscall
  solely for the test.
- [x] **P1-B03 Before snapshot:** record the baseline after boot and before the
  cycle's write/edit/compile/run work.
- [x] **P1-B04 After snapshot:** record after child wait, file close, artifact
  removal, and shell return, but before QEMU quits.
- [x] **P1-B05 Per-cycle assertion:** compare before/after values inside every
  one of the 100 boots, not only after the final filesystem check.
- [x] **P1-B06 Diagnostic:** on mismatch, report cycle number, owner PID, frame
  delta, handle delta, and retained child state.
- [x] **P1-B07 Existing checks:** retain editor, compiler, run, cleanup, and
  final GFS2 consistency assertions.

Exit condition: 100 functional cycles pass and every cycle independently
returns frames and handles to baseline before reboot masks a leak.

### P1-C - Complete ATA failure injection

- [x] **P1-C01 Fault contract:** define three distinct validation outcomes:
  out-of-range capacity, device `ERR`, and poll timeout.
- [x] **P1-C02 ERR hook:** add a validation-image-only path that forces the ATA
  error-status branch.
- [x] **P1-C03 Timeout hook:** add a validation-image-only path that forces the
  bounded polling timeout branch.
- [x] **P1-C04 Range fixture:** retain the existing short-disk capacity test.
- [x] **P1-C05 Separate tests:** boot one image per fault and require a distinct
  marker, bounded completion, and absence of `ATAOK`.
- [x] **P1-C06 Release exclusion:** prove normal images contain neither forced
  fault mode.
- [x] **P1-C07 Lane integration:** require all three fault classes in the QEMU
  release lane.

Exit condition: the campaign proves capacity bounds, the hardware `ERR` path,
and timeout handling separately.

### P1-D - Make syscall/import ABI parity machine-readable

- [x] **P1-D01 Import table:** add `gwo2-import-abi-v1.tsv` with every import's
  ID, name, argc, result shape, and syscall selector or `runtime-only` marker.
- [x] **P1-D02 Process mapping:** include the explicit mappings
  `15->0x0f`, `16->0x10`, `17->0x11`, `18->0x12`, and `19->0x13`.
- [x] **P1-D03 Full parser:** replace selected-line checks with a validator that
  parses every row in both ABI tables.
- [x] **P1-D04 Structural checks:** reject duplicate IDs/names/selectors,
  unknown result kinds, missing rows, wrong argc, and unmapped syscall imports.
- [x] **P1-D05 Generated NASM:** generate named syscall/import constants and
  consume them from the kernel instead of numeric process-ABI magic values.
- [x] **P1-D06 Host declarations:** generate or validate the corresponding C
  verifier and Rust bootstrap declarations from the same table.
- [x] **P1-D07 Grown parity:** validate `grc1` import lowering against the table
  with a corpus until the Grown source can consume generated declarations.
- [x] **P1-D08 Stale-generation gate:** fail validation when generated ABI files
  differ from their TSV source.
- [x] **P1-D09 Mutation tests:** mutate every column family and require the
  contract failure lane to reject it.

Exit condition: adding or changing any syscall/import requires one
machine-readable row and cannot silently drift across kernel, verifier, Rust,
Grown, and documentation surfaces.

### P1-E - Reproduce releases from two isolated clean checkouts

- [x] **P1-E01 Archive A:** export tracked `HEAD` with `git archive` into a new
  temporary directory.
- [x] **P1-E02 Archive B:** independently export the same `HEAD` into a second
  temporary directory.
- [x] **P1-E03 Independent builds:** build compiler, image, and manifest inside
  each archive without consulting the caller's `build/`, `dist/`, untracked
  files, or generated cache.
- [x] **P1-E04 Equality:** compare compiler bytes, image bytes, and manifest
  bytes between A and B.
- [x] **P1-E05 Poison fixture:** place a plausible untracked input in the
  original worktree and prove neither archive build consumes it.
- [x] **P1-E06 Dirty-tree rule:** define whether the release command rejects a
  dirty caller tree or reports that it built committed `HEAD`; do not silently
  mix the two identities.
- [x] **P1-E07 Lane integration:** replace the same-working-tree proof in the
  formal release target while retaining its fast form for local iteration.

Exit condition: the release artifacts depend only on tracked `HEAD` and the
documented toolchain, not on local files.

### P2-A - Split the NASM kernel without changing one output byte

This is source modularization, not a rewrite and not a move to Rust or C.

- [x] **P2-A01 Baseline:** record the pre-refactor kernel/image SHA-256 and the
  exact build command from a fixed commit.
- [x] **P2-A02 Include root:** make `kernel/longmode_boot.asm` an ordered include
  driver while preserving all constants, symbol order, sections, padding, and
  binary layout.
- [x] **P2-A03 Entry/arch:** move boot entry, long-mode transition, GDT, IDT,
  interrupt, and syscall entry into `kernel/entry.asm` and
  `kernel/arch/x86_64/` one contiguous block at a time.
- [x] **P2-A04 Memory:** move frame, paging, and heap code into `kernel/mm/`.
- [x] **P2-A05 Processes:** move process and scheduler code into `kernel/proc/`.
- [x] **P2-A06 Drivers:** move ATA and console/keyboard code into
  `kernel/drivers/`.
- [x] **P2-A07 Filesystem:** move GFS2 code into `kernel/fs/gfs2.asm`.
- [x] **P2-A08 Runtime:** move the GWO2 loader/verifier and native GrVM bootstrap
  into `kernel/runtime/`.
- [x] **P2-A09 Per-move identity:** after every move, require the assembled
  kernel and complete image to be byte-identical to the recorded baseline.
- [x] **P2-A10 Final gates:** run static, QEMU, fixed-point, fault, and release
  validation after the last include split.

Exit condition: maintainers can navigate subsystem files while the flat binary
is unchanged. P2 must finish before a native backend expands kernel/runtime
complexity further.

### P3 - Native backend remains parked

- [ ] Do not start native code generation before every P0 and P1 exit condition
  is closed and the formal Alpha milestone is recorded.
- [ ] Do not pull networking, GUI, USB, SMP, UEFI, package management, POSIX,
  or dynamic linking into this hardening plan.
- [ ] Treat native backend planning as a new contract phase with executable
  format, relocation, memory-permission, and parity gates of its own.

## Formal `Self-Hosting Alpha 1` unlock

The milestone/tag may be created only when:

1. all P0 defects are closed with three-path compiler parity where required;
2. all P1 gates pass, including exhaustive process-create failure injection;
3. the 100-cycle campaign proves zero frame and handle deltas before every
   reboot;
4. ATA capacity, device `ERR`, and timeout paths are independently proven;
5. two isolated `git archive HEAD` builds produce identical compiler, image,
   and manifest bytes;
6. syscall/import ABI rows are validated in full and generated constants are
   current;
7. the two-clean-boot `grc2 == grc3` fixed point still passes; and
8. documentation records commands, tool versions, durations, resource limits,
   unsupported hardware, and any intentionally deferred P2/P3 work.

P2 source modularization may land before or immediately after the tag, but it
must preserve byte identity and must complete before P3 native-backend work.
