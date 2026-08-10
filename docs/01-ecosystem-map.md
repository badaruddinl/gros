# Ecosystem Map

This document maps the current GrOS ecosystem layers and their status. It is a
status document only. It does not add a compiler, parser, interpreter, linker,
allocator, executable loader, kernel implementation, hosted output, or boot
banner change.

## Current Layer Stack

```txt
Gr ecosystem
  GrOS
    GrBoot
    GrRT16
    GrABI
    GrSCall
    Grogan        implemented bootstrap seeds; full kernel future
  Grown
    .grw          seed/spec source form
  GWN
    .gwn          implemented raw native/backend source
  GWO
    .gwo          implemented raw artifacts, headered form reserved
```

## Status Table

| Layer | Role | Current Status |
| --- | --- | --- |
| Gr | Broad ecosystem identity | seed/spec |
| GrOS | Operating-system workspace/product | implemented seed |
| GrBoot | Boot sector and boot chain | implemented seed |
| GrRT16 | Real16 stage-2 runtime | implemented seed |
| GrABI | Handoff, calling, memory, and profile contracts | seed/spec with validation |
| GrSCall | Gr System Call service interface | implemented seed through `int 30h` |
| Grown | Native low-level systems language | seed/spec only |
| GWN | Low-level native/backend source layer | implemented for raw boot/stage source |
| GWO | Object/output artifact form | implemented as raw artifacts |
| Grogan | Kernel/bootstrap ownership seeds | implemented seed; full kernel reserved/future |

## Implemented Today

Implemented and validated in the repository:

- 512-byte GrOS v0.5 BIOS boot sector.
- Stage-1 BIOS loader.
- 2048-byte stage-2 payload reservation.
- Stage-2 load to `0000:8000`.
- Prompt with `ground>`.
- Built-in commands: `help`, `ver`, `cls`, `reboot`.
- GWN raw builder: `scripts/gwnraw.sh`.
- GWO raw artifacts under `dist/`.
- GrSCall seed through `int 30h`.
- Runtime services:
  - `runtime/control.probe`
  - `runtime/control.version`
  - `runtime/control.profile_id`
  - `console/text.write_cstr`
  - `console/text.write_char`
  - `console/text.write_crlf`
- Static validation for boot, stage-2, runtime ABI, real16 memory, near pointers,
  stage-2 data, generated-code fixtures, and policy rules.
- BIOS-to-x86_64 long-mode transition seed with boot-info and E820 discovery.
- x86_64 IDT installation and fail-stop exception proof.
- E820-backed frame ownership, bounded bitmap heap, and timer-preemptive task
  queue, and boot-resident read-only filesystem seed.

The current GrBoot boot chain status is:

```txt
docs/21-grboot-boot-chain-status.md
```

The current GrABI contract status is:

```txt
docs/22-grabi-contract-status.md
```

The current GWO artifact status is:

```txt
docs/23-gwo-artifact-status.md
```

The current implementation readiness gate is:

```txt
docs/24-implementation-readiness-status.md
```

The current GrRT16 runtime status is:

```txt
docs/20-grrt16-runtime-status.md
```

## Seeded But Not Complete

Seeded contracts and bounded implementations:

- Grown `.grw` front-end shape.
- Generated-code fixture representation.
- Minimal Grown `fn main()` runtime contract.
- Real16 memory model.
- Calling convention seed.
- `.gwo` payload header shape.
- `.gwo` raw-profile versus future headered-executable boundary.
- BIOS-to-x86_64 transition and initial x86_64 machine ownership.
- Exception, physical-memory, bootstrap-heap, preemptive-task, and boot-filesystem
  seeds.

These are contracts, not complete toolchain or kernel implementation.

## Reserved Layers

Reserved/future layers:

- Grogan kernel proper beyond the bounded bootstrap seeds.
- Headered `.gwo` executable loader.
- Grown parser.
- Grown compiler.
- Grown interpreter.
- Type checker.
- Linker.
- Relocation model.
- General physical-frame allocator, paging, and heap beyond bounded seeds.
- Process/task isolation, context switching, and preemptive scheduling.
- General filesystem, block-device drivers, and writable storage.
- General hardware IRQ/device delivery and recoverable exception handling.
- x86_64 GrOS runtime profile integration beyond the transition seed.
- aarch64 and riscv64 native profiles.
- Hosted-native executable outputs.

## Profile Model

Current concrete profile:

```txt
gros.x86.bios.real16.stage2.v0
```

The first x86_64 Grogan product seed is:

```txt
gros.x86.bios.longmode.grogan.v0
```

It is bootable and validated, but remains a bounded bootstrap profile rather
than a complete kernel runtime.

Future native profile names may include:

```txt
gros.x86_64.uefi.v0
gros.aarch64.uefi.v0
gros.riscv64.machine.v0
```

The transition mechanism is also registered as a machine bootstrap seed:

```txt
x86.bios.longmode.transition.v0
```

It proves the BIOS-to-x86_64 handoff backing the product profile above; it is not
itself a complete Grogan kernel.

Future hosted compatibility profile names may include:

```txt
host.linux.x86_64.v0
host.windows.x86_64.v0
host.darwin.aarch64.v0
```

Hosted profiles are compatibility/adoption surfaces. They are not replacements
for native GrOS.

The Grogan kernel seed boundary is defined in:

```txt
docs/19-grogan-kernel-seed.md
```

The canonical profile status registry is:

```txt
docs/18-profile-registry.md
```

## Development Rule

New layers should follow this order:

```txt
contract -> validation -> implementation -> claim
```

When a component lacks validation, it must remain `seed/spec` or
`reserved/future`.
