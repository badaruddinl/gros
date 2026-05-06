# GrOS Profile Registry

This document defines the first GrOS profile registry seed. It is a registry and
status contract only. It does not add a new profile implementation, parser,
compiler, interpreter, linker, allocator, executable loader, hosted-native
output, UEFI target, `x86_64` execution, GrCall profile query service, profile
version bump, or boot banner change.

## Purpose

Profiles name execution environments, ABI contracts, artifact compatibility
classes, and hosted compatibility surfaces. A profile name must not imply that a
target is implemented unless the repository has source, artifacts, and
validation for that target.

Status words follow:

```txt
implemented      present in this repository and validated
seed/spec        specified as an initial contract, not complete implementation
reserved/future  named as a direction, not claimed as working
```

## Current Implemented Profile

| Profile | Class | Status | Evidence |
| --- | --- | --- | --- |
| `gros.x86.bios.real16.stage2.v0` | GrOS runtime profile | implemented seed | stage-2 `.gwn` source, `.gwo` artifacts, runtime ABI checks, memory model checks, QEMU smoke |

This profile is:

```txt
x86 BIOS
16-bit real mode
stage-2 payload loaded at 0000:8000
not x86_64
not UEFI
not Grogan proper
```

## Backing Machine Profile

| Profile | Class | Status | Evidence |
| --- | --- | --- | --- |
| `x86.bios.real16.stage2.v0` | machine handoff profile | seed/spec | documented by the stage-1 to stage-2 handoff and ABI profile docs |

This machine profile backs the current GrOS runtime profile. It is lower-level
than Grown and lower-level than Grogan. It defines the machine handoff shape that
GrRT16 currently relies on.

## Reserved Native GrOS Profiles

These names are reserved for future GrOS-native targets. They are not
implemented by this repository today.

| Profile | Class | Status |
| --- | --- | --- |
| `gros.x86_64.uefi.v0` | native GrOS profile | reserved/future |
| `gros.aarch64.uefi.v0` | native GrOS profile | reserved/future |
| `gros.riscv64.machine.v0` | native GrOS profile | reserved/future |

Reserved native profile names do not imply:

```txt
protected mode
long mode
UEFI boot
page tables
interrupt controller support
native drivers
Grogan kernel implementation
```

## Reserved Hosted Compatibility Profiles

These names are reserved for future hosted-native compatibility targets. They
are adoption surfaces for Grown and GrOS-shaped runtime semantics on another OS.
They are not replacements for native GrOS.

| Profile | Class | Status |
| --- | --- | --- |
| `host.linux.x86_64.v0` | hosted compatibility profile | reserved/future |
| `host.windows.x86_64.v0` | hosted compatibility profile | reserved/future |
| `host.darwin.aarch64.v0` | hosted compatibility profile | reserved/future |

Reserved hosted profile names do not imply:

```txt
host executable output
host syscall adapter
host standard library
host ABI backend
package manager integration
```

## GWO Header Profile IDs

The `.gwo` header seed reserves a numeric `profile_id` field. This registry does
not assign numeric profile IDs yet.

Current status:

```txt
profile_id numeric mapping is reserved/future
header-aware loader is not implemented
profile query service is not implemented
```

A future profile ID assignment must define:

- symbolic profile name,
- numeric `profile_id`,
- supported header version,
- allowed flags,
- payload class,
- entry validation rules,
- rejection behavior.

## GrCall Profile Rule

The current GrCall entry mechanism is:

```txt
int 30h
```

This is specific to:

```txt
gros.x86.bios.real16.stage2.v0
```

Future profiles may use another machine entry mechanism while preserving stable
service semantics where possible. A different machine entry mechanism must be
documented by that profile before it is implemented.

## Registration Rules

- Unknown profile names are unsupported.
- A profile may be listed as `reserved/future` without implementation.
- A profile may be listed as `seed/spec` when a written contract exists but
  complete source, artifacts, or validation do not.
- A profile may be listed as `implemented` only when source, artifacts, and
  validation exist in this repository.
- A profile must not change meaning after being published.
- Profile-specific raw `gwn(...)` boundaries must match the target profile or be
  explicitly allowed by a future cross-profile rule.
- Hosted profiles must stay clearly marked as compatibility/adoption surfaces.

## Relationship To Other Documents

Relevant profile contracts:

```txt
docs/05-stage2-contract.md
docs/06-abi-handoff.md
docs/09-grown-ecosystem-mapping.md
docs/10-runtime-abi-seed.md
docs/11-gwo-payload-header.md
docs/13-abi-stability-gate.md
docs/14-real16-memory-model.md
docs/17-grcall-service-registry.md
docs/19-grogan-kernel-seed.md
docs/20-grrt16-runtime-status.md
docs/21-grboot-boot-chain-status.md
docs/22-grabi-contract-status.md
```

## Non-Goals

This registry does not add:

- a new boot profile
- UEFI loading
- protected mode
- long mode
- an `x86_64` runtime
- an `aarch64` runtime
- a hosted-native executable backend
- `.grw` compiler output
- a headered `.gwo` loader
- a profile ID numeric mapping
- a GrCall profile query service
- a Grogan kernel implementation
- a profile version bump
- a version bump
