# GrOS Runtime ABI Seed

This document defines the first runtime ABI seed for Grown and GrOS stage-2 payloads. It is a profile contract with minimal runtime/control and console/text services. It does not add a syscall table, compiler, interpreter, parser, `.gn` toolchain, hosted-native output, or boot banner change.

## Profile

```txt
gros.x86.bios.real16.stage2.v0
```

Current machine mode:

```txt
x86 BIOS real mode, 16-bit
```

This is not an `x86_64` profile.

## Function Call Seed

The seed calling convention is for future `.gn` lowering and `.gr` ground layer code that runs inside the GrOS stage-2 profile.

Argument registers:

```txt
AX  argument 0
BX  argument 1
CX  argument 2
DX  argument 3
```

Additional arguments are passed on the stack, right to left, as 16-bit words.

Return registers:

```txt
AX     primary return value
DX:AX  32-bit return value when a profile explicitly requires it
```

Caller-saved registers:

```txt
AX BX CX DX FLAGS
```

Callee-saved registers:

```txt
SI DI BP SP DS ES SS
```

Direction flag must be clear on function entry and on return.

## Stack Rules

The stack starts from the stage-2 handoff state:

```txt
SS = 0000
SP = 7C00
```

Rules:

- Stack entries are 16-bit words.
- The stack grows downward.
- The caller owns pushed arguments.
- The callee must restore `SP` before return.
- No heap, allocator, or stack probing contract exists yet.

## Runtime Service Gate

The current GrOS runtime service gate is:

```txt
int 30h
```

The stage-2 image installs this real-mode interrupt vector at boot. The current implementation exposes only the services defined below.

Service selector:

```txt
AH  service group
AL  service id
```

Argument registers:

```txt
BX CX DX SI DI
```

Return convention:

```txt
CF = 0  success, result in AX
CF = 1  error, error code in AX
```

Service calls may clobber caller-saved registers unless a future service definition says otherwise.

Interrupt handlers must return through `iret`. To return `CF` to the caller, the handler must update the saved FLAGS word in the interrupt stack frame before `iret`.

## Implemented Services

### Runtime/control Probe

```txt
AH = 00h
AL = 00h
```

Inputs:

```txt
none beyond the selector in AX
```

Success return:

```txt
CF = 0
AX = 0000h
```

Meaning:

```txt
int 30h is installed and the runtime/control group can answer the probe.
```

Unsupported selectors return:

```txt
CF = 1
AX = 0001h
```

`0001h` means unsupported service selector.

### Console/text Write C String

```txt
AH = 01h
AL = 00h
```

Inputs:

```txt
DS:SI  NUL-terminated byte string
```

Success return:

```txt
CF = 0
AX = 0000h
```

Meaning:

```txt
Write each byte from `DS:SI` until the first `00h` byte.
```

The current implementation writes through BIOS teletype output. It does not define colors, cursor policy beyond BIOS behavior, page selection, encoding beyond bytes, or CR/LF normalization.

The service preserves `SI` so callers can reuse the original string pointer after the call.

## Initial Service Groups

These groups are reserved for future specification, except where an implemented service is explicitly listed:

```txt
00h  runtime/control, AL=00h probe implemented
01h  console/text, AL=00h write C string implemented
02h  storage/block
03h  process/task
04h  memory
```

No other service IDs are implemented yet.

## Failure And Halt Behavior

Returning from the stage-2 entrypoint is undefined.

Runtime fatal behavior is reserved. A future profile may define:

- halt
- reboot
- panic text
- structured error code
- return to monitor

Until then, payloads must choose their own halt or loop behavior.

## Executable Artifact Seed

For the current GrOS stage-2 profile, executable payload layout remains the stage-2 raw payload inside:

```txt
dist/gros-stage2.gro
```

Future `.gro` executable subformats are reserved. They must define:

- header shape
- entrypoint representation
- relocation rules
- symbol visibility
- service import rules
- profile compatibility marker

## Non-Goals

This seed does not add:

- additional `int 30h` services beyond runtime/control probe and console/text write C string
- a syscall table
- a standard library
- `.gn` code generation
- `.gro` executable headers
- protected mode or long mode
- `x86_64` execution
