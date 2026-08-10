# Grogan Syscall and User Boundary Seed

The Grogan x86_64 profile now has a deliberately bounded user boundary. It is
an executable seed for the Developer Preview, not a general process model.

## Contract

`syscall_seed` configures:

- `IA32_EFER.SCE`;
- `IA32_STAR` with kernel CS `0x18` and SYSRET base `0x20`;
- `IA32_LSTAR` at `syscall_entry`;
- `IA32_FMASK` masking IF on entry.

The GDT adds DPL3 data selector `0x2b` and DPL3 64-bit code selector `0x33`.
The page-table second 2 MiB window is user-accessible, while the first 2 MiB
remains kernel-owned.

## `.gwo` loader

`grw_grogan_x86_64.sh` emits the bounded GWO1 artifact consumed by the image
builder. The loader validates magic, version, 24-byte header size, non-zero
payload size (maximum 128 bytes), entry offset zero, and byte-sum checksum
before copying the payload to `0x200000`.

The phase-7 payload uses two stable selectors:

```txt
1  write proof and return through SYSRETQ
2  exit the bounded user payload into the kernel shell path
```

There is no arbitrary file loading, relocation, signal model, user page
allocator, or asynchronous user interrupt delivery yet.

## Evidence

```bash
make grogan-syscalls
make grogan-syscall-failures
make grogan-x86_64-qemu
```

The ordered debug proof is:

```txt
SCFGGWO1SC1SC2USEROK
```

The static negative test removes both SYSRETQ opcodes and verifies that the
validator rejects the image.
