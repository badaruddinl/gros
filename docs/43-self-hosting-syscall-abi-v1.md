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
| `0x0b` | `process_exit` | does not return |
| `0x0c` | `task_yield` | zero, or error |
| `0x0d` | `path_create` | handle, or error |
| `0x0e` | `file_unlink` | zero, or error |
| `0x0f` | `process_spawn` | child PID, or error |
| `0x10` | `process_wait` | child PID, or error |
| `0x11` | `process_spawn_args` | child PID, or error |
| `0x12` | `process_args` | bytes copied, or error |
| `0x13` | `file_list` | bytes copied, or error |

`file_open` and `path_create` receive a NUL-terminated root filename in `RDI`
with a maximum of 31 bytes. Read/write calls receive `(handle, buffer,
length)` in `RDI`, `RSI`, and `RDX`; zero-length reads are successful no-ops,
while a zero-length `file_write` truncates the file at offset zero. Alpha v1
currently exposes one process-local handle with an offset, owner PID, and
closed state.

`process_spawn_args` extends `process_spawn` with `(image, size, args,
args_len)`. The first three values use `RDI`, `RSI`, and `RDX`; the fourth value
is transported in `R8` because the x86-64 `SYSCALL` instruction overwrites
`RCX` with the return address. The argument block is at most 256 bytes and
contains NUL-separated strings with a trailing NUL. `process_args(buffer,
capacity)` copies the current process's complete block and returns its byte
length; it returns `-ENOSPC` rather than truncating arguments.

`file_list(buffer, capacity)` returns a NUL-separated list of root-directory
file names and returns `-ENOSPC` if the complete listing does not fit.

## Errors and blocking

Alpha reserves `-EFAULT`, `-EINVAL`, `-ENOENT`, `-EEXIST`, `-EBADF`, `-EIO`,
`-ENOMEM`, `-ENOSYS`, `-ECHILD`, `-EAGAIN`, and `-ENOSPC`. The current calls are
bounded and non-blocking: `console_read` and `process_wait` return `-EAGAIN`,
and userland yields before retrying. A future blocking implementation must
change the process state to `blocked` and wake only after the documented event;
it must never spin with interrupts disabled.

## Batch 1.2 gate

The contract is ready for implementation when fixtures prove exact register
selectors, negative errors, path/length limits, partial I/O semantics, handle
ownership, and rejection of a buffer crossing a page boundary.
