.PHONY: build check test run clean

build:
	./scripts/build_boot.sh

check: build
	./scripts/check_boot.sh

test:
	./scripts/test_grraw.sh

run: build
	./scripts/run_qemu.sh

clean:
	rm -rf build/*.gro
