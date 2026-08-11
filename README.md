# GrOS / Gr Ecosystem Development Repository

Gr is an ecosystem that starts from the most basic machine bytes and grows upward into native GrOS systems code.

- `.grw` = Ground Readable Weave, the main Grown source form
- `.gwo` = Grown Object, the compiled/output artifact form
- `.gwn` = Ground/Woven Native, the low-level native/backend layer

This repository is the development workspace for GrOS v0.5: a 512-byte x86 BIOS boot sector with a small interactive prompt.

```txt
GrOS v0.5
ground>
```

The prompt supports line editing with Backspace and built-in commands:

- `help` prints the available commands.
- `ver` prints the current GrOS version.
- `cls` clears the screen.
- `reboot` restarts through BIOS bootstrap.

## Current GrOS Profile

- CPU/firmware: x86 BIOS real mode
- Runtime profile: `gros.x86.bios.real16.stage2.v0`
- x86_64 bootstrap profile: `gros.x86.bios.longmode.grogan.v0`
- Profile registry: [docs/18-profile-registry.md](docs/18-profile-registry.md)
- Product output: `build/gros-v0.5.gwo`
- Product form: raw 512-byte boot sector

## Technical Specs

- [Naming](docs/00-naming.md)
- [Ecosystem map](docs/01-ecosystem-map.md)
- [File role model](docs/02-grw-gwo-gwn.md)
- [First bytes](docs/03-first-bytes.md)
- [Raw `.gwn` format](docs/04-raw-gwn-format.md)
- [Stage-1 to stage-2 boot contract](docs/05-stage2-contract.md)
- [GrOS ABI handoff profile](docs/06-abi-handoff.md)
- [Grown language spec](docs/07-grown-language.md)
- [Project overview](docs/08-project-overview.md)
- [Grown hosted-native ecosystem mapping](docs/09-grown-ecosystem-mapping.md)
- [GrOS runtime ABI seed](docs/10-runtime-abi-seed.md)
- [`.gwo` payload header seed](docs/11-gwo-payload-header.md)
- [Grown `.grw` front-end seed](docs/12-grw-front-end-seed.md)
- [ABI stability gate](docs/13-abi-stability-gate.md)
- [Real16 memory model seed](docs/14-real16-memory-model.md)
- [Generated-code fixture contract seed](docs/15-generated-code-fixture-contract.md)
- [Grown main runtime contract seed](docs/16-grown-main-runtime-contract.md)
- [GrSCall service registry](docs/17-grscall-service-registry.md)
- [Profile registry](docs/18-profile-registry.md)
- [Grogan kernel seed](docs/19-grogan-kernel-seed.md)
- [GrRT16 runtime status](docs/20-grrt16-runtime-status.md)
- [GrBoot boot chain status](docs/21-grboot-boot-chain-status.md)
- [GrABI contract status](docs/22-grabi-contract-status.md)
- [GWO artifact status](docs/23-gwo-artifact-status.md)
- [Implementation readiness status](docs/24-implementation-readiness-status.md)
- [QEMU interaction contract](docs/25-qemu-interaction-contract.md)
- [GrABI generated-code compatibility](docs/26-grabi-generated-code-compatibility.md)
- [Headered stage-2 loader contract](docs/27-headered-stage2-loader-contract.md)
- [Minimal-main compiler subset](docs/28-minimal-main-compiler-subset.md)
- [Release readiness handoff](docs/29-release-readiness-handoff.md)
- [Grogan real16 seed](docs/31-grogan-real16-seed.md)
- [BIOS to x86_64 long-mode transition seed](docs/32-long-mode-transition-contract.md)
- [Grogan x86_64 BIOS profile seed](docs/38-grogan-x86_64-profile.md)
- [Grogan syscall and user boundary seed](docs/39-grogan-syscall-user-boundary.md)
- [Grogan compiler preview](docs/40-grogan-compiler-preview.md)
- [GrOS Self-Hosting Alpha roadmap](docs/41-self-hosting-alpha-roadmap.md)
- [Self-Hosting process and address-space contract](docs/42-self-hosting-process-address-space-contract.md)
- [Self-Hosting syscall ABI v1](docs/43-self-hosting-syscall-abi-v1.md)
- [Self-Hosting GFS2 and block contract](docs/44-self-hosting-gfs2-block-contract.md)
- [Self-Hosting GWO2 and Grown Alpha contract](docs/45-self-hosting-gwo2-grown-alpha-contract.md)
- [Self-Hosting Alpha kernel foundation](docs/46-self-hosting-alpha-kernel-foundation.md)
- [Self-Hosting Alpha storage foundation](docs/47-self-hosting-alpha-storage-foundation.md)
- [Self-Hosting Alpha GWO2 toolchain](docs/48-self-hosting-alpha-gwo2-toolchain.md)
- [Self-Hosting Alpha kernel GWO2 VM bridge](docs/49-self-hosting-alpha-kernel-gwo2-vm.md)
- [Self-Hosting Alpha evidence](docs/50-self-hosting-alpha-evidence.md)
- [x86_64 exception and interrupt foundation](docs/33-x86_64-exception-interrupt-foundation.md)
- [physical memory ownership seed](docs/34-physical-memory-ownership.md)
- [kernel heap seed](docs/35-kernel-heap-seed.md)
- [Grogan scheduler and preemption seed](docs/36-cooperative-scheduler-seed.md)
- [boot-resident filesystem seed](docs/37-boot-filesystem-seed.md)

## Stage-2 Loader Target

The experimental stage-2 image keeps the `GrOS v0.5` banner and moves the prompt runtime behind a 512-byte stage-1 loader.

- Stage-1 source: `boot/stage1_loader.gwn`
- Stage-2 source: `boot/stage2_min.gwn`
- Boot-chain status: [docs/21-grboot-boot-chain-status.md](docs/21-grboot-boot-chain-status.md)
- Product output: `build/gros-stage2.gwo`
- Product form: 512-byte stage-1 plus a 32-byte header and 2016-byte stage-2 payload
- Runtime gate: `int 30h`
- Implemented runtime services: `runtime/control.probe`, `console/text.write_cstr`, and `console/text.write_char`

Build and validate:

```bash
make stage2
make check-stage2
make runtime-abi
make grabi-generated-code
make minimal-main
make minimal-main-qemu
make headered-stage2-rejection
make release-ready
make headered-stage2
```

## Grogan x86_64 Developer Preview

The Grogan x86_64 profile now forms a useful bounded Developer Preview: BIOS to
long mode, owned frames and heap, timer-preemptive task contexts, a read-only
filesystem shell, a DPL3 GWO1 user payload, two syscalls, and a tiny compiler
slice that produces the payload consumed by the image builder. It is not a
general-purpose kernel or compiler.

```bash
make grogan-x86_64-image
make grogan-x86_64-image-failures
make grogan-compiler
make grogan-syscalls
make grogan-x86_64-qemu
make grogan-shell-qemu
```

Run the QEMU smoke start:

```bash
make smoke-stage2
```

Exercise the deterministic prompt interactions under QEMU:

```bash
make qemu-interaction
```

Run interactively:

```bash
make run-stage2
```

## Run

Ubuntu / WSL:

```bash
sudo apt update
sudo apt install qemu-system-x86 git make nasm
```

Build:

```bash
./scripts/build_boot.sh
```

The boot image is built from the raw-byte `.gwn` source in `boot/` through `scripts/gwnraw.sh`. The source format supports labels plus absolute and relative label references, so boot code can move without manually recalculating offsets.

Check size and boot signature:

```bash
./scripts/check_boot.sh
```

Run builder tests:

```bash
make test
```

Run the full validation path:

```bash
make validate-static
make validate-qemu
make validate-release
```

The static lane runs the project policy guard, generated-code fixture validator,
headered `.gwo` candidate fixture validator, raw builder tests, generated boot
image checks, committed `dist` artifact checks, and build output parity checks.
The QEMU lane runs the positive stage-2, minimal-main, malformed-header, and
long-mode traces. Each lane reports its duration and preserves failures.
`make validate` remains a compatibility alias for `make validate-static` and
requires `ndisasm` from the `nasm` package. Disassembly is validation-only; for
the current boot artifacts, the build source of truth remains `.gwn` raw source
and Bash tooling.

The runtime ABI, real16 memory model, near-pointer, and stage-2 data fixtures are Bash-only and validate the implemented `int 30h` return contracts, seeded memory boundaries, pointer immediates, and static text/data bytes directly from the stage-2 `.gwo` image.

Run only the headered `.gwo` candidate fixture validator:

```bash
make gwo-header-fixtures
```

This validates fixture bytes only. It does not load or execute a headered
`.gwo` payload.

Run in QEMU:

```bash
./scripts/run_qemu.sh
```

Or use the Makefile:

```bash
make run
```

## Naming Philosophy

Public meaning:

```txt
Grw = Ground Readable Weave
Gwo = Grown Object
Gwn = Ground/Woven Native
```

The original private meaning can remain implicit.
