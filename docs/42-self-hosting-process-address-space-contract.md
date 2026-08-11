# Self-Hosting Alpha Process and Address-Space Contract

This contract opens Batch 1.1. It describes the process boundary required by
Self-Hosting Alpha; it does not claim that the current two-task bootstrap has
implemented it.

## Process identity and lifecycle

Every executable receives a non-zero `pid` and an owned process object with:

```txt
pid, parent_pid, state, exit_status
page_root, user_stack, heap_break
kernel_stack, saved_context
handle_table, owned_frames
```

The only lifecycle states are `new`, `ready`, `running`, `blocked`, and
`exited`. A parent may reap an exited child exactly once. Teardown releases the
child's handles, user mappings, frames, and kernel stack before its PID can be
reused.

## Virtual layout

Alpha uses 4 KiB pages and a separate page root per process:

| Region | Range | Permission | Owner |
| --- | --- | --- | --- |
| Kernel identity/bootstrap | `0x00000000..0x003fffff` | supervisor RW/NX | kernel |
| User image and heap | `0x00400000..0x3fffffff` | user RW/NX | process |
| User guard | one unmapped page below stack | none | process |
| User stack | top of user range, downward | user RW/NX | process |
| Kernel stack | outside user page tables | supervisor RW/NX | kernel |

User mappings must never expose page-table pages, kernel text, the IDT, the
TSS, the frame database, or another process's pages. The initial user stack is
page-aligned and receives only validated argv data.

## Entry and return invariants

- A process enters at a verified user entry point with `CS=0x33`, `SS=0x2b`,
  interrupts enabled only after its kernel stack is selected, and a canonical
  `RSP`.
- `SYSCALL` saves the user `RIP`, `RFLAGS`, and `RSP` before switching to the
  process's kernel stack. The kernel never trusts a user-supplied return frame.
- `SYSRETQ` is used only with canonical user `RIP`/`RSP` and the fixed DPL3
  selectors.
- An interrupt or exception from ring 3 enters the TSS `RSP0` stack and returns
  through a validated frame.

## Fault and ownership rules

- A user page fault, invalid opcode, general protection fault, or bad syscall
  pointer records a diagnostic and exits only that process.
- A fault while executing kernel code remains fail-stop and emits a distinct
  kernel-fault marker.
- `copy_from_user` and `copy_to_user` validate the complete range before the
  first byte is accessed; partial unchecked copies are forbidden.
- Freeing an unowned frame, double freeing a frame, or tearing down a live
  mapping is a kernel invariant failure.

## Batch 1.1 gate

The contract is ready for implementation when the negative fixtures prove:

1. a user mapping cannot overlap a supervisor mapping;
2. a non-canonical pointer is rejected without a write;
3. an unmapped user fault becomes a process exit, not `EX06` kernel halt; and
4. process teardown returns every owned frame and handle exactly once.

The first runtime demonstration is checkpoint C1 from the roadmap: two ring-3
programs run independently and one may fault without stopping the other.
