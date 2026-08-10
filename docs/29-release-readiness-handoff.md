# Release Readiness Handoff

The current `development` baseline is release-ready for its declared seed scope.
The reproducible gate is:

```bash
make validate-release
```

It runs the static/negative lane and the positive QEMU lane as separate measured
steps. The QEMU lane includes normal stage-2 smoke and interaction cases, the
compiled minimal-main payload trace, malformed-header runtime rejection, and the
BIOS-to-x86_64 transition trace. A clean Git worktree after this gate is the
final handoff condition.

## Implemented Evidence

| Phase | Evidence |
| --- | --- |
| 0 | deterministic development validation baseline |
| 1 | QEMU prompt interaction transcript gate |
| 2 | expected-only `grabi.real16.call.v1` fixture validation |
| 3 | fixed v1 headered stage-2 loader and rejection contract |
| 4 | minimal `.grw` main compiler through headered QEMU execution |
| 5 | CRLF and line-comment normalization with bounded parser rejection |
| 6 | QEMU proof malformed header does not execute `0000:8020` |
| 7 | `release-ready` aggregate gate and this handoff |
| 10 | BIOS boot-info/E820 to x86_64 long-mode transition seed |
| 11 | x86_64 IDT installation and fail-stop invalid-opcode exception proof |
| 12 | E820-backed, page-aligned physical-frame ownership seed |
| 13 | bounded, aligned bootstrap heap inside owned physical frame |
| 14 | heap-backed timer-preemptive task contexts, round-robin return, and completion states |
| 15 | boot-resident read-only filesystem lookup and heap-backed read |
| 16 | Grogan x86_64 product profile marker, entry contract, and QEMU ownership trace |
| 17 | PIC/PIT timer and keyboard IRQ stubs with explicit frame/`iretq` validation |
| 18 | bounded GWO1 syscall/user boundary with `SCFGGWO1SC1SC2USEROK` proof |
| 19 | Grogan compiler preview lowered into the embedded GWO1 payload |
| 20 | deterministic compiler/image rebuild and artifact-mutation parity check |

## Scope Boundaries

This readiness claim does not claim a general Grown compiler, general executable
loader, call-ABI code generation, complete kernel, general allocator,
general device/IRQ model, recoverable fault handling, or a general scheduler beyond the bounded timer contexts,
userspace process model, general filesystem, block-device driver, UEFI, or
hosted-native output. The repository contains the bounded
`gros.x86.bios.longmode.grogan.v0` product profile plus its transition, physical
memory, heap, preemptive task-context, and filesystem seeds.
The compiler accepts only the documented Grogan smoke `main` subset and emits a
checksum-validated 41-byte GWO1 payload. It does not claim general scheduling
beyond the bounded context switching seed, task isolation, writable filesystem,
arbitrary executable loading, or block-device support.

## Handoff Commands

```bash
make validate-static
make validate-qemu
make validate-release
git status --short --branch
```

Expected release evidence includes a successful gate, matching `build` and
tracked `dist` boot artifacts, passing QEMU traces, and no uncommitted files.
