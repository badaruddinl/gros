# GrOS / Gr Ecosystem Development Repository

Gr is an ecosystem that starts from the most basic machine bytes.

- `.gr` = low-level source / root / grain
- `.gro` = build output / grown form

This repository is the development workspace for GrOS v0.1: a 512-byte x86 BIOS boot sector that prints:

```txt
GrOS v0.1
```

## Initial Target

- CPU/firmware: x86 BIOS real mode
- Product output: `build/gros-v0.1.gro`
- Initial product form: raw 512-byte boot sector

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

Check size and boot signature:

```bash
./scripts/check_boot.sh
```

Run in QEMU:

```bash
./scripts/run_qemu.sh
```

Or use the Makefile:

```bash
make run
```

## Git Initialization

```bash
git init
git add .
git commit -m "birth: GrOS v0.1 boot sector"
```

## Naming Philosophy

Public meaning:

```txt
Gr  = root / grain / ground
Gro = grown form
```

The original private meaning can remain implicit.
