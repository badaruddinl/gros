# Grogan Real16 Seed

Grogan is implemented as a narrow real16 kernel seed inside the current fixed
stage-2 reservation. `grogan_entry` is the payload entry at `0000:8020`.
It owns the `GRGN` state block, initialization status, panic-code slot, and the
`int 30h` GrSCall handler. GrRT16 prompt behavior remains a hosted early runtime
service under this ownership.

The seed has no scheduler, allocator, process model, filesystem, mode switch,
or userspace. `scripts/check_grogan_seed.sh` protects the entry/state/dispatch
boundary; existing QEMU interaction proves the hosted runtime still boots.
