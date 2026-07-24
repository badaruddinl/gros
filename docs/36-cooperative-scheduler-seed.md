# Cooperative Scheduler Seed

The bootstrap scheduler allocates two 24-byte task descriptors from the kernel
heap. A descriptor contains `next`, `entry`, and `state`; `scheduler_run`
walks the linked run queue, calls each runnable entry, then changes its state
to completed.

The initial tasks emit `T1` and `T2`, so QEMU proves FIFO cooperative dispatch
through `HEAPT1T2`. There is no timer/preemption, saved register context,
separate task stacks, blocking, wakeup, or multicore scheduling yet.
