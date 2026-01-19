.PHONY: build release install clean test

build:
	zig build

release:
	zig build release-fast

install: release
	sudo cp zig-out/bin/stump /usr/local/bin/ && echo "success"

clean:
	rm -rf zig-out .zig-cache

test:
	zig build test
