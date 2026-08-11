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
| Language | Typed Grown subset with functions, locals, control flow, arrays, and modules |
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

## Current implementation checkpoint (feature/self-hosting-alpha)

The following roadmap work is now implemented and covered by executable gates:

| Area | Evidence | Status |
| --- | --- | --- |
| GWO2 v2 verifier and GrVM parity | `make gwo2-host gwo2-host-failures` | complete |
| Rust bootstrap compiler | `scripts/grc0.sh` (`tools/grc0.rs`) | complete |
| Grown compiler subset (`grc1.grw`) | `make grogan-compiler grogan-compiler-failures` | complete |
| Hosted compiler fixed point | `make grogan-self-host` | complete |
| Ring-3 GWO2 execution and GFS2 syscalls | `make grogan-processes grogan-storage` and their QEMU gates | complete |
| In-OS compile/run and persistence | `make grogan-self-host-qemu` | complete |

The hosted fixed-point proof compares the output produced by `grc1.gwo` with
the next output produced by that Grown compiler; it does not incorrectly
compare the Rust bootstrap seed with the canonical Grown output. The C host
verifier/VM is retained only as a reference oracle. `make validate-self-host`
is the short gate for both hosted and in-OS proofs; the full Phase 10 release
gate still requires the reliability, mutation, and reproducible-distribution
work listed above.
