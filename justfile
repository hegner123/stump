build:
    zig build
    go build -o stump-mcp

release:
    zig build release-fast
    go build -o stump-mcp

install: release
    sudo cp zig-out/bin/stump-core /usr/local/bin/ && codesign -s - /usr/local/bin/stump-core && echo "stump-core installed"
    sudo cp stump-mcp /usr/local/bin/stump && codesign -s - /usr/local/bin/stump && echo "stump installed"

clean:
    rm -rf zig-out .zig-cache stump-mcp

test:
    zig build test
    go test -v
