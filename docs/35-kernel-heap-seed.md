# Kernel Heap Seed

The owned E820 frame now hosts a bounded kernel slot heap. Its first 16 bytes
remain reserved for the `FRM1` ownership marker; the remaining 255 slots are
16-byte units tracked by a bitmap. `heap_alloc` rounds requests to slot units,
finds contiguous free slots, detects arithmetic overflow, and rejects requests
past the frame end. `heap_free` validates ownership, alignment, range, and size
before returning slots to the bitmap.

Bootstrap allocates 32 then 64 bytes and writes `HEP1` and `HEP2`, frees the
second allocation, and allocates it again as `HFR1`. QEMU emits `HEAP` only
after allocation, free, and reuse all succeed.

This is intentionally not a general allocator: there is no coalescing, growth
beyond one frame, multi-frame heap, or concurrent access protocol.
