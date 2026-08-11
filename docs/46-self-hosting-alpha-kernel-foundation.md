# Self-Hosting Alpha Kernel Foundation

This document records the first implementation checkpoint after the contracts
in docs 42–45. It is deliberately narrower than the Self-Hosting Alpha
release gate.

## Implemented

- E820 page frames are tracked in a 768-entry database with allocation bits and
  process owner ids. Double free and cross-owner free requests are rejected.
- The bootstrap root keeps supervisor identity mappings for the kernel and
  gives each process an owned PML4/PDPT/PD/PT chain. User code, a guard page,
  a user stack, and later heap pages are 4 KiB mappings.
- A real 64-bit TSS is loaded. Each process has a kernel stack and `RSP0` is
  updated whenever the scheduler changes address spaces.
- Two independent ring-3 process objects have PID/state/CR3/page ownership,
  full timer contexts, syscall return state, exit status, and deterministic
  frame teardown.
- `copy`-style user-span validation walks every PTE before console writes.
  Vector 14 classifies a user page fault as a process exit; kernel faults still
  fail closed. The QEMU fixture faults both processes and reaches the kernel
  shell without a kernel stop.
- `mem_grow` allocates and maps an owned page before committing the new break.

## Evidence

```bash
make grogan-processes grogan-process-failures
make grogan-process-qemu
```

The positive QEMU trace contains two user exits for the normal payload and two
recoverable guard-page faults for the isolation fixture. The static gate checks
the TSS load, CR3/PT construction, user-pointer page walk, timer context handoff,
and fault vector.

## Still deliberately open

The bootstrap executable is still the transitional GWO1 native payload. ATA,
the in-kernel GFS2 mount, dynamic process spawning/wait handles, and the GWO2
bytecode VM remain later roadmap batches. The kernel-resident emergency shell
also remains until ring-3 userland is integrated.
