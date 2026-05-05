# GrOS / Gr Ecosystem Development Repository

Gr is an ecosystem that starts from the most basic machine bytes.

- `.gr` = low-level source / root / grain
- `.gro` = build output / grown form

This repository is the development workspace for GrOS v0.5: a 512-byte x86 BIOS boot sector with a small interactive prompt.

```txt
GrOS v0.5
gr>
```

The prompt supports line editing with Backspace and built-in commands:

- `help` prints the available commands.
- `ver` prints the current GrOS version.
- `cls` clears the screen.
- `reboot` restarts through BIOS bootstrap.

## Current Target

- CPU/firmware: x86 BIOS real mode
- Product output: `build/gros-v0.5.gro`
- Product form: raw 512-byte boot sector

## Technical Specs

- [Raw `.gr` format](docs/04-raw-gr-format.md)
- [Stage-1 to stage-2 boot contract](docs/05-stage2-contract.md)

## Run

Ubuntu / WSL:

```bash
sudo apt update
sudo apt install qemu-system-x86 git make
```

Build:

```bash
./scripts/build_boot.sh
```

The boot image is built from the raw-byte `.gr` source in `boot/` through `scripts/grraw.sh`. The source format supports labels plus absolute and relative label references, so boot code can move without manually recalculating offsets.

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

This runs the raw builder tests, checks the generated boot sector, checks the committed `dist/` artifact, and verifies that `build/gros-v0.5.gro` matches `dist/gros-v0.5.gro`. If `ndisasm` is installed, the validation script also disassembles the generated image and checks the expected BIOS interrupt path. Disassembly is validation-only; the build source of truth remains the `.gr` raw source and Bash tooling.

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
Gr  = root / grain / ground
Gro = grown form
```

The original private meaning can remain implicit.
