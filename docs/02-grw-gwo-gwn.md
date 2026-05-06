# .grw, .gwo, and .gwn

The Gr ecosystem uses three related file roles.

## .grw

`.grw` is Ground Readable Weave. It is the main readable Grown source form for
the GrOS ecosystem.

Example roles:

- GrOS kernel source
- GrOS driver source
- runtime service source
- ABI/profile-aware library source
- hosted-native compatibility source
- profile-specific payload source

## .gwo

`.gwo` is Grown Object. It is the compiled/output artifact form for the GrOS
ecosystem.

Example roles:

- boot image
- stage payload
- kernel image
- executable image
- library package
- SDK bundle

Hosted-native profiles may also produce native executable formats for their host OS. Those files are compatibility outputs, not replacements for `.gwo` as the GrOS ecosystem artifact.

## .gwn

`.gwn` is Ground/Woven Native. It is the low-level native/backend layer that
stays closest to machine bytes and remains the source of truth for the current
boot and stage code.

Example roles:

- raw byte source
- boot loader source
- machine-entry source
- ABI/profile-specific backend source
- low-level kernel or driver source

Grown `.grw` is designed to sit above raw `.gwn` while still being able to cross a raw ground boundary when a target profile needs direct machine, ABI, syscall, or executable-format control.

## Mapping

Native GrOS mode:

```txt
.grw source -> .gwn ground layer -> .gwo artifact
```

Hosted-native mode:

```txt
.grw source -> .gwn host profile layer -> native host executable
```

## Target Meaning

In GrOS documentation, target means an execution profile, ABI profile, device profile, machine profile, payload profile, or hosted-native compatibility profile.

Hosted-native profiles let Grown code run on another operating system as a native executable for that host. The intent is ecosystem adoption: the program runs on the host, but its language, runtime model, and low-level ground layer remain shaped by GrOS.

## Meaning

Public meaning:

```txt
.grw = Ground Readable Weave
.gwo = Grown Object
.gwn = Ground/Woven Native
```

The original private meaning stays implicit.
