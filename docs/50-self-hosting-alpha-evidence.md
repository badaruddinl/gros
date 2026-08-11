# Self-Hosting Alpha Evidence

This document records the bounded, reproducible evidence for the current
Self-Hosting Alpha implementation. It is a test record, not a claim that the
later Phase 10 reliability gate has already been completed.

## Hosted proof

Run from the repository root on a clean Rust toolchain:

```bash
make gwo2-host gwo2-host-failures
make grogan-compiler grogan-compiler-failures
make grogan-self-host
```

`grogan-self-host` performs these real steps in a temporary directory:

1. Compile `examples/grown-alpha/grc1.grw` with the Rust bootstrap
   `tools/grc0.rs` into `grc1.gwo`.
2. Execute `grc1.gwo` with the host GrVM; it emits `grc2.gwo`.
3. Execute `grc2.gwo` twice and require the second artifact to be byte-equal
   to the first.

The equality is between two Grown-produced artifacts. The Rust seed is a
bootstrap input and is not expected to have identical local-slot numbering.

## In-OS proof

```bash
make grogan-self-host-qemu
```

The image builder embeds the Rust-produced compiler artifact and its source in
GFS2. The QEMU script boots without host filesystem access, sends `b` to the
ring-3 shell to compile `grc1.grw`, sends `x` to load and execute the persisted
`grc2.gwo`, and then checks the GFS2 volume for that artifact. It also requires
the `COMPILE OK` and `RUN OK` markers emitted by the shell.

## Deliberate Alpha limits

The current proof is bounded by the Alpha contract: one GWO2 bytecode section,
64 VM frames, 32 pages of literal storage, bounded call depth and patch table,
one shell-managed child workflow, and the existing GFS2 image size. Modules,
arrays/records as richer language types, hardware error injection, and the
100-cycle Phase 10 reliability campaign remain explicit follow-on work. No
release claim should be inferred from static signatures alone.
