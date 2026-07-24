# Physical Memory Ownership Seed

The long-mode transition now turns the BIOS E820 map into one concrete physical
ownership decision. The first MiB is permanently reserved for firmware and
bootstrap state. The seed scans E820 entries at `0000:6000` and accepts only a
type-1 usable range whose first fully contained, 4 KiB-aligned page is in
`00100000h..001fffffh`, the initial identity-mapped window.

The first selected 4 KiB frame becomes `phys_first_free`; the seed writes the
physical marker `FRM1` there. QEMU must emit `PMEMF1` before the controlled
invalid-opcode proof. This establishes that the selected frame was both
available by E820 policy and writable under the active page map.

This is not a general physical-frame allocator yet: it does not track free
lists, split ranges, reclaim boot memory, support memory above 2 MiB, or expose
allocation/deallocation to other kernel subsystems.
