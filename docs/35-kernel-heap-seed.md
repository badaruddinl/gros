# Kernel Heap Seed

The owned E820 frame now hosts a bounded kernel bump heap. Its first 16 bytes
remain reserved for the `FRM1` ownership marker; `heap_next` begins after that
marker and `heap_end` is exactly one page later. `heap_alloc` rounds requests
to 16-byte alignment, detects arithmetic overflow, and rejects any request
past the frame end.

Bootstrap allocates 32 then 64 bytes and writes `HEP1` and `HEP2`. QEMU emits
`HEAP` only after both allocations and writes succeed.

This is intentionally not a reclaiming allocator: there is no `free`, block
metadata, coalescing, growth beyond one frame, or concurrent access protocol.
