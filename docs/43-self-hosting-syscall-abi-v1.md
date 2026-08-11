# Self-Hosting Alpha Syscall ABI v1

This contract opens Batch 1.2. It replaces the two-marker syscall seed with a
stable, checked interface for userland and the compiler runtime.

## Calling convention

The existing `SYSCALL` entry remains the transport. Registers are:

```txt
RAX selector
RDI, RSI, RDX, R10, R8, R9 arguments 0..5
RAX signed result (non-negative value or negative -errno)
RCX/R11 kernel-owned saved return state
```

All selectors are 32-bit values. Unknown selectors return `-ENOSYS` and never
enter a fail-stop path. Arguments are interpreted only after scalar overflow
and user-range checks.

## Selector table

| Selector | Name | Result |
| ---: | --- | --- |
| `0x01` | `console_read` | bytes read, or error |
| `0x02` | `console_write` | bytes written, or error |
| `0x03` | `file_open` | process-local handle, or error |
| `0x04` | `file_read` | bytes read, EOF is zero |
| `0x05` | `file_write` | bytes written, or error |
| `0x06` | `file_close` | zero, or error |
| `0x07` | `file_stat` | zero, or error |
| `0x08` | `mem_grow` | previous break, or error |
| `0x09` | `process_spawn` | child PID, or error |
| `0x0a` | `process_wait` | child PID, or error |
| `0x0b` | `process_exit` | does not return |
| `0x0c` | `task_yield` | zero, or error |
| `0x0d` | `path_create` | handle, or error |
| `0x0e` | `file_unlink` | zero, or error |

`file_open` and `path_create` receive a NUL-terminated path in `RDI` with a
maximum of 255 bytes. Read/write calls receive `(handle, buffer, length)` in
`RDI`, `RSI`, and `RDX`; `length=0` is a successful no-op. Every handle has an
access mode, offset, owner PID, and closed state.

## Errors and blocking

Alpha reserves `-EFAULT`, `-EINVAL`, `-ENOENT`, `-EEXIST`, `-EBADF`, `-EIO`,
`-ENOMEM`, `-ENOSYS`, `-ECHILD`, `-EAGAIN`, and `-ENOSPC`. A blocking call
changes the process state to `blocked`; the scheduler wakes it only after the
documented event. A syscall never spins with interrupts disabled while waiting
for user input or disk I/O.

## Batch 1.2 gate

The contract is ready for implementation when fixtures prove exact register
selectors, negative errors, path/length limits, partial I/O semantics, handle
ownership, and rejection of a buffer crossing a page boundary.
