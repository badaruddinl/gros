# Grogan Scheduler and Context Seed

The bootstrap scheduler allocates two 40-byte task descriptors from the kernel
heap. A descriptor contains `next`, `entry`, `state`, and a saved interrupt
context pointer. `scheduler_run` still exercises each entry once and records its
completion state during bootstrap; after that seed check, the entries are
replaced with independently stacked task contexts.

The PIT timer stub saves all general-purpose registers, hands the interrupted
frame to `scheduler_tick`, and returns through the selected task's frame. The
first timer interrupt saves the shell context, then round-robins task one,
task two, and the shell context. The independent task entries emit `P1` and
`P2`, then wait for the next timer interrupt, so QEMU proves an actual context
switch rather than only a function call. There is still no blocking/wakeup API,
multicore scheduling, or user-task isolation.

The static contract is checked by `scripts/check_grogan_scheduler.sh` and its
negative self-test; the QEMU lane requires both `P1` and `P2` in addition to the
shell transcript.
