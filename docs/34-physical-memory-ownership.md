# Physical Memory Ownership Seed

The Grogan x86_64 profile turns the BIOS E820 map into a bounded physical-frame
pool. The first MiB is permanently reserved for firmware and bootstrap state.
The seed scans E820 entries at `0000:6000` and accepts only type-1 usable ranges
whose fully contained, 4 KiB-aligned pages are in
`00100000h..003fffffh`, the identity-mapped bootstrap window.

The first selected frame becomes `phys_first_free`; a second frame is allocated,
written with `FRM2`, and returned to the free bitmap. QEMU must emit
`PMEMF1F2` before the controlled invalid-opcode proof. This establishes that
the pool can allocate and release frames that were both available by E820 policy
and writable under the active page map.

This is still a bounded physical-frame allocator: it tracks at most 64 pages in
the first 4 MiB, does not merge E820 ranges, reclaim boot memory, support memory
above the mapped window, or expose allocation/deallocation as a public ABI.
