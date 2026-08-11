# Self-Hosting Alpha Kernel GWO2 VM Bridge

The long-mode kernel now consumes the same GWO2 artifact emitted by the hosted
Rust bootstrap compiler. The image builder generates
`build/generated/grogan-user.gwo`, the installed `grc1.gwo`, and the compiler
source in GFS2. The kernel embeds those exact artifacts; it does not consult a
host path after image creation.

## Load and verify

Before creating a process, the kernel checks the GWO2 magic, version, target,
kind, reserved fields, one-section layout, exact image size, image FNV-1a, and
section FNV-1a. Its bounded verifier then checks instruction lengths, local
indexes, stack underflow/maximum depth, import signatures, jump ranges, and
instruction-boundary targets. Only the verified bytecode is copied into the
process code page.

## Ring-3 execution

Each process receives the fixed native GrVM entry plus the verified bytecode at
an isolated offset in its RX code page. The deterministic stack VM keeps its
operand stack and 64 locals in the process's RW user stack page, bounds every
fetch and step count, and lowers imports through the normal syscall ABI:

```txt
print_i32(i32) -> console_write + decimal conversion
newline()     -> console_write(\n)
exit(i32)     -> process_exit
return/halt   -> process_exit
const_bytes   -> bounded NUL-terminated bytes in the process VM pool
file_open/read/write/close/stat -> checked GFS2 file syscalls
path_create/unlink -> checked GFS2 metadata syscalls
load_byte/store_byte -> validated process-memory byte access
```

The VM saves its program counter, operand depth, and step counter in user
memory before each syscall and reloads them after return. This makes syscall
register clobbering explicit rather than relying on an undocumented register
preservation accident.

## Evidence

```bash
make grogan-compiler grogan-processes
make grogan-x86_64-qemu grogan-process-qemu
make grogan-self-host-qemu
```

The QEMU trace contains `GWO2OK`, two VM-produced `28` outputs, normal process
exit markers, and a separate fault-injection run where both ring-3 guard-page
faults reach `USEROK` without halting the kernel.

The shell's `b` command runs the installed compiler source in ring 3 and writes
`grc2.gwo` through the normal GFS2 syscalls; `x` loads that persisted artifact
through the same verifier and runs it. The QEMU self-host gate checks the
compile status, run status, and persisted artifact. Host fixed-point equality
is checked by `make grogan-self-host`; the two gates are intentionally kept
separate so a host proof cannot mask an in-OS failure.
