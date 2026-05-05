# .gr, .gn, and .gro

The Gr ecosystem uses three related file roles.

## .gr

`.gr` is ground/root/raw source. It stays closest to machine bytes and remains the source of truth for the current boot and stage code.

Example roles:

- raw byte source
- boot loader source
- machine-entry source
- ABI/profile-specific backend source
- low-level kernel or driver source

## .gn

`.gn` is unified Grown source. Grown is the native low-level systems language for the GrOS ecosystem.

Example roles:

- GrOS kernel source
- GrOS driver source
- runtime service source
- ABI/profile-aware library source
- hosted-native compatibility source
- profile-specific payload source

Grown `.gn` is designed to sit above raw `.gr` while still being able to cross a raw ground boundary when a target profile needs direct machine, ABI, syscall, or executable-format control.

## .gro

`.gro` is the canonical grown artifact for the GrOS ecosystem.

Example roles:

- boot image
- stage payload
- kernel image
- executable image
- library package
- SDK bundle

Hosted-native profiles may also produce native executable formats for their host OS. Those files are compatibility outputs, not replacements for `.gro` as the GrOS ecosystem artifact.

## Mapping

Native GrOS mode:

```txt
.gn source -> .gr ground layer -> .gro artifact
```

Hosted-native mode:

```txt
.gn source -> .gr host profile layer -> native host executable
```

## Target Meaning

In GrOS documentation, target means an execution profile, ABI profile, device profile, machine profile, payload profile, or hosted-native compatibility profile.

Hosted-native profiles let Grown code run on another operating system as a native executable for that host. The intent is ecosystem adoption: the program runs on the host, but its language, runtime model, and low-level ground layer remain shaped by GrOS.

## Meaning

Public meaning:

```txt
.gr  = grain / ground / root
.gn  = Grown native unified source
.gro = grown form
```

The original private meaning stays implicit.
