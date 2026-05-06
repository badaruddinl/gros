# GrRT16 Runtime Status

This document records the current implemented status of GrRT16, the real-mode
16-bit stage-2 runtime seed. It is a status and validation map only. It does not
add a runtime service, kernel implementation, parser, compiler, interpreter,
linker, allocator, executable loader, hosted-native output, profile version
bump, or boot banner change.

## Purpose

GrRT16 is the current runtime layer behind the stage-2 GrOS prompt. It exists to
prove the first runtime boundary before Grogan, generated Grown code, or richer
`.gwo` executable loading exists.

Current status:

```txt
GrRT16: implemented seed
```

Current visible baseline:

```txt
GrOS v0.5
ground>
```

## Current Profile

GrRT16 currently runs under:

```txt
gros.x86.bios.real16.stage2.v0
```

Machine environment:

```txt
x86 BIOS real mode
16-bit
stage-2 payload loaded at 0000:8000
```

This is not an `x86_64` profile, not UEFI, and not Grogan proper.

## Source And Artifact Boundary

Current GrRT16 source:

```txt
boot/stage2_min.gwn
```

Current stage-2 artifacts:

```txt
build/gros-stage2.gwo
dist/gros-stage2.gwo
```

Current build truth remains:

```txt
.gwn source -> scripts/gwnraw.sh -> .gwo artifact
```

No `.grw` source is parsed, compiled, lowered, or emitted into GrRT16 today.

## Boot Handoff Input

GrRT16 is entered by GrBoot stage-1 after the stage-2 payload has been read from
disk.

The current handoff shape is:

```txt
LBA 0     512-byte stage-1 BIOS loader
LBA 1..4  2048-byte stage-2 payload
entry     0000:8000
```

The handoff contracts are defined by:

```txt
docs/05-stage2-contract.md
docs/06-abi-handoff.md
docs/21-grboot-boot-chain-status.md
```

GrRT16 must not depend on stage-1 labels, buffers, strings, padding bytes, or
temporary state.

## Runtime Initialization

The current GrRT16 stage-2 entry initializes:

- `DS = 0000`,
- `ES = 0000`,
- `SS = 0000`,
- `SP = 7C00`,
- direction flag clear,
- `int 30h` interrupt vector offset and segment.

After the GrSCall gate is installed, GrRT16 probes:

```txt
00h:00h runtime/control.probe
```

This proves that the current runtime service gate can answer the probe before
the prompt loop starts.

## User-Facing Runtime

The current user-facing runtime owns:

- the `GrOS v0.5` banner,
- the `ground>` prompt,
- basic line editing with Backspace,
- a 16-byte command input buffer,
- command dispatch for `help`, `ver`, `cls`, and `reboot`,
- unknown-command output as `?`.

The implemented commands are:

| Command | Current Behavior |
| --- | --- |
| `help` | prints the available command names |
| `ver` | prints `GrOS v0.5` |
| `cls` | clears the screen through BIOS video mode reset |
| `reboot` | restarts through BIOS bootstrap |

The prompt is runtime code, not a shell, process model, user environment, or
filesystem interface.

## GrSCall Runtime Services

GrRT16 currently installs the GrSCall entry gate:

```txt
int 30h
```

Selector encoding:

```txt
AH = service group
AL = service id
```

Return convention:

```txt
CF = 0  success, result in AX
CF = 1  error, error code in AX
```

Implemented selectors:

| Selector | Name | Status |
| --- | --- | --- |
| `00h:00h` | `runtime/control.probe` | implemented |
| `01h:00h` | `console/text.write_cstr` | implemented |
| `01h:01h` | `console/text.write_char` | implemented |

Unsupported selectors return:

```txt
CF = 1
AX = 0001h
```

The current console services write through BIOS teletype output. That BIOS usage
is the current implementation detail, not a complete console driver model.

The service contracts are defined by:

```txt
docs/10-runtime-abi-seed.md
docs/17-grscall-service-registry.md
```

## Memory And Data Status

GrRT16 uses the current real16 memory seed:

```txt
docs/14-real16-memory-model.md
```

Important current ranges:

```txt
07000h..07BFFh  conservative stack region
07C00h..07DFFh  stage-1 load area, not stable runtime data
08000h..087FFh  stage-2 payload image
```

Current data status:

- static strings live inside the stage-2 payload image,
- the command buffer starts in zero-filled stage-2 padding,
- near pointers are 16-bit offsets in segment `0000`,
- no heap exists,
- no allocator exists,
- no relocation model exists,
- no far-pointer model exists.

## Validation Map

GrRT16 status is validated by direct checks over source and `.gwo` artifacts.

| Check | What It Protects |
| --- | --- |
| `scripts/check_stage2_image.sh` | stage-2 image size, boot signature, loader transfer, `int 30h` install, prompt strings |
| `scripts/check_runtime_abi.sh` | implemented GrSCall selectors and return paths |
| `scripts/check_memory_model.sh` | real16 memory ranges and stage-2 setup bytes |
| `scripts/check_near_pointers.sh` | near-pointer immediates used by stage-2 |
| `scripts/check_stage2_data.sh` | static text/data bytes and zero-filled command buffer tail |
| `scripts/smoke_stage2_qemu.sh` | QEMU smoke start for the stage-2 image |

The full local validation path remains:

```bash
make validate
make smoke-stage2
```

Validated image facts today:

- the full stage-2 boot image is 2560 bytes,
- stage-1 is 512 bytes,
- stage-2 payload is 2048 bytes,
- the stage-1 boot signature is `55aa`,
- stage-1 reads the stage-2 payload to `0000:8000`,
- stage-1 jumps to `0000:8000`,
- stage-2 contains `GrOS v0.5`,
- stage-2 contains `ground> `.

## Change Rules

Changes to GrRT16 must keep the status model precise.

Rules:

- A new GrSCall selector must update the runtime ABI seed, the GrSCall service
  registry, and static runtime ABI validation.
- A prompt or command behavior change must keep stage-2 image validation and
  data fixtures green.
- A memory ownership change must update the real16 memory model before it is
  claimed as implemented.
- A loader, headered `.gwo`, or generated `.grw` path must stay outside GrRT16
  status until its own contract and validation exist.
- GrRT16 must not be renamed or described as Grogan proper.

## Relationship To Grogan

Grogan is the future GrOS kernel proper. GrRT16 is the current stage-2 runtime
seed.

Current relationship:

```txt
GrBoot loads GrRT16 today.
GrRT16 exposes the first GrSCall seed.
Grogan remains reserved/future.
```

The Grogan seed boundary is defined by:

```txt
docs/19-grogan-kernel-seed.md
```

## Relationship To Status Documents

Relevant source-of-truth documents:

```txt
docs/00-naming.md
docs/01-ecosystem-map.md
docs/05-stage2-contract.md
docs/06-abi-handoff.md
docs/10-runtime-abi-seed.md
docs/13-abi-stability-gate.md
docs/14-real16-memory-model.md
docs/17-grscall-service-registry.md
docs/18-profile-registry.md
docs/19-grogan-kernel-seed.md
docs/21-grboot-boot-chain-status.md
docs/22-grabi-contract-status.md
docs/23-gwo-artifact-status.md
docs/24-implementation-readiness-status.md
```

This document summarizes current GrRT16 status. It does not override those
contracts.

## Non-Goals

GrRT16 does not currently provide:

- Grogan kernel implementation,
- complete syscall ABI,
- user/kernel separation,
- process, task, or thread model,
- scheduler,
- heap allocator,
- virtual memory,
- paging,
- protected mode,
- long mode,
- UEFI loading,
- `x86_64` execution,
- filesystem services,
- storage services,
- device driver model,
- executable `.gwo` loader,
- `.grw` parser,
- `.grw` compiler,
- `.grw` interpreter,
- hosted-native executable output,
- a profile version bump,
- a GrOS boot banner change.
