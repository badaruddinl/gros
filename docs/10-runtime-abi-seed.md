# GrOS Runtime ABI Seed

This document defines the first runtime ABI seed for Grown and GrOS stage-2 payloads. It is a profile contract with minimal runtime/control and console/text services. It does not add a syscall table, compiler, interpreter, parser, `.grw` toolchain, hosted-native output, or boot banner change.

## Profile

```txt
gros.x86.bios.real16.stage2.v0
```

Current machine mode:

```txt
x86 BIOS real mode, 16-bit
```

This is not an `x86_64` profile.

The current runtime status for this profile is defined in:

```txt
docs/20-grrt16-runtime-status.md
```

The broader GrABI contract status is defined in:

```txt
docs/22-grabi-contract-status.md
```

## Function Call Seed

The seed calling convention is for future `.grw` lowering and `.gwn` ground layer code that runs inside the GrOS stage-2 profile.

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

This is the current `GrSCall.real16.int30` seed. GrSCall is the canonical
service-call name for the GrOS ecosystem. The current seed is not a complete OS
syscall ABI.

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

### Console/text Write Character

```txt
AH = 01h
AL = 01h
```

Inputs:

```txt
BL  byte to write
```

Success return:

```txt
CF = 0
AX = 0000h
```

Meaning:

```txt
Write the byte in `BL`.
```

The current implementation writes through BIOS teletype output. It does not define colors, page selection, encoding beyond bytes, or control-character policy beyond BIOS behavior.

## Static ABI Fixture

The implemented return contracts are checked by:

```txt
scripts/check_runtime_abi.sh
```

The fixture reads the built stage-2 `.gwo` bytes and verifies:

- the `runtime/control.probe` call shape
- the `console/text.write_cstr` selector call shape
- the `console/text.write_char` selector call shape
- the interrupt handler stack frame
- the unsupported selector error path
- the success return path
- `SI` preservation for C string writes

This fixture is static validation only. It does not emulate or execute a `.grw` payload.

## Initial Service Groups

These groups are reserved for future specification, except where an implemented service is explicitly listed:

```txt
00h  runtime/control, AL=00h probe implemented
01h  console/text, AL=00h write C string and AL=01h write character implemented
02h  storage/block
03h  process/task
04h  memory
```

No other service IDs are implemented yet.

## Memory Model

The current memory model seed for this runtime profile is defined in:

```txt
docs/14-real16-memory-model.md
```

The seed keeps near pointers as 16-bit offsets in segment `0000`, reserves far pointers, and does not define a heap. Pointer-sized `.grw` types remain reserved until memory fixtures and generated-code validation exist.

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
dist/gros-stage2.gwo
```

Future `.gwo` executable subformats are reserved. They must define:

- header shape
- entrypoint representation
- relocation rules
- symbol visibility
- service import rules
- profile compatibility marker

## Non-Goals

This seed does not add:

- additional `int 30h` services beyond runtime/control probe, console/text write C string, and console/text write character
- a syscall table
- a standard library
- `.grw` code generation
- `.gwo` executable headers
- protected mode or long mode
- `x86_64` execution
