.PHONY: build check run clean

build:
	./scripts/build_boot.sh

check: build
	./scripts/check_boot.sh

run: build
	./scripts/run_qemu.sh

clean:
	rm -rf build/*.gro
