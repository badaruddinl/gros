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
- Profile registry: [docs/18-profile-registry.md](docs/18-profile-registry.md)
- Product output: `build/gros-v0.5.gwo`
- Product form: raw 512-byte boot sector

## Technical Specs

- [Naming](docs/00-naming.md)
- [Ecosystem map](docs/01-ecosystem-map.md)
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
- [GrCall service registry](docs/17-grcall-service-registry.md)
- [Profile registry](docs/18-profile-registry.md)
- [Grogan kernel seed](docs/19-grogan-kernel-seed.md)
- [GrRT16 runtime status](docs/20-grrt16-runtime-status.md)
- [GrBoot boot chain status](docs/21-grboot-boot-chain-status.md)

## Stage-2 Loader Target

The experimental stage-2 image keeps the `GrOS v0.5` banner and moves the prompt runtime behind a 512-byte stage-1 loader.

- Stage-1 source: `boot/stage1_loader.gwn`
- Stage-2 source: `boot/stage2_min.gwn`
- Boot-chain status: [docs/21-grboot-boot-chain-status.md](docs/21-grboot-boot-chain-status.md)
- Product output: `build/gros-stage2.gwo`
- Product form: 512-byte stage-1 plus a 2048-byte stage-2 payload
- Runtime gate: `int 30h`
- Implemented runtime services: `runtime/control.probe`, `console/text.write_cstr`, and `console/text.write_char`

Build and validate:

```bash
make stage2
make check-stage2
make runtime-abi
```

Run the QEMU smoke start:

```bash
make smoke-stage2
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
make validate
```

This runs the project policy guard, generated-code fixture validator, raw builder tests, generated boot image checks, committed `dist` artifact checks, and build output parity checks. `make validate` requires `ndisasm` from the `nasm` package. Disassembly is validation-only; for the current boot artifacts, the build source of truth remains `.gwn` raw source and Bash tooling.

The runtime ABI, real16 memory model, near-pointer, and stage-2 data fixtures are Bash-only and validate the implemented `int 30h` return contracts, seeded memory boundaries, pointer immediates, and static text/data bytes directly from the stage-2 `.gwo` image.

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
