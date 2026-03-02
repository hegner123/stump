# Stump - Token-Efficient Directory Tree MCP Tool

[![Test](https://github.com/hegner123/stump/actions/workflows/test.yml/badge.svg)](https://github.com/hegner123/stump/actions/workflows/test.yml)
[![Release](https://github.com/hegner123/stump/actions/workflows/release.yml/badge.svg)](https://github.com/hegner123/stump/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A high-performance MCP server tool that provides compact, token-efficient directory tree visualization optimized for LLM consumption.

## Features

- **Token-Efficient Output**: 50%+ reduction vs standard tree tools through compact JSON format
- **Configurable Depth**: Control traversal depth to limit output size
- **Smart Filtering**: Include/exclude by extension, pattern, or hidden files
- **Symlink Handling**: Detect symlinks by default, optionally follow with cycle detection
- **Safety Safeguards**: Large directory detection with override capability
- **Dual Output Modes**:
  - Stdout mode with configurable token limits (1k-100k tokens)
  - File mode for unlimited tree sizes
- **Performance Metrics**: Optional detailed timing, memory, and filesystem operation tracking
- **Error Resilience**: Distinguishes fatal warnings from non-fatal errors
- **Cross-Platform**: macOS, Linux, and Windows

## Quick Start

### Prerequisites

- Zig 0.15.2 or later

### Build

```bash
# Development build
zig build

# Optimized release build (recommended for production)
zig build -Doptimize=ReleaseFast

# Alternative release modes
zig build release-safe   # Safety checks enabled
zig build release-fast   # Maximum performance
zig build release-small  # Minimal binary size
```

The compiled binary will be in `zig-out/bin/stump` (Unix) or `zig-out\bin\stump.exe` (Windows).

### CLI Usage

Stump can be used directly from the command line:

```bash
# Basic usage
stump .                           # Current directory
stump ~/projects -d 3             # Max depth 3
stump src --exclude-ext log,tmp   # Filter extensions
stump . --no-hidden               # Hide hidden files
stump . -o tree.json              # Output to file
stump . --modified                # Include modification timestamps
stump . --follow-symlinks         # Follow symlinks with cycle detection
stump . --performance             # Include performance metrics
stump . --token-limit 50000       # Custom token limit
```

#### CLI Flags

| Flag | Description |
|------|-------------|
| `-h`, `--help` | Show help message |
| `-d`, `--depth <N>` | Max traversal depth (-1 for unlimited, default: -1) |
| `-o`, `--output <file>` | Output to file instead of stdout |
| `--include-ext <ext,...>` | Only include files with these extensions |
| `--exclude-ext <ext,...>` | Exclude files with these extensions |
| `--exclude <pattern,...>` | Exclude paths matching glob patterns |
| `--hidden` / `--no-hidden` | Show/hide hidden files (default: show) |
| `--size` / `--no-size` | Show/hide file sizes (default: show) |
| `--modified` / `--no-modified` | Show/hide modification timestamps (default: hide) |
| `--follow-symlinks` | Follow symbolic links (with cycle detection) |
| `--force` | Bypass large directory safeguards |
| `--performance` | Include performance metrics in output |
| `--token-limit <N>` | Token limit for stdout mode (1000-100000, default: 10000) |

Run `stump --help` for all options.

### Installation as MCP Server

Add to your MCP client configuration:

```bash
# Basic installation (default 10k token limit)
claude mcp add --transport stdio stump -- /path/to/zig-out/bin/stump

# With custom token limit via environment variable
claude mcp add --transport stdio stump -- env STUMP_TOKEN_LIMIT=20000 /path/to/zig-out/bin/stump
```

### Testing

```bash
# Run all tests
zig build test

# Run only unit tests
zig build test-unit

# Run only integration tests
zig build test-integration
```

## Usage

### Basic Tree Visualization

```json
{
  "method": "tools/call",
  "params": {
    "name": "stump",
    "arguments": {
      "dir": "~/projects/myapp"
    }
  }
}
```

### With Depth Limit and Filtering

```json
{
  "method": "tools/call",
  "params": {
    "name": "stump",
    "arguments": {
      "dir": "~/projects/myapp",
      "depth": 3,
      "exclude_ext": ["log", "tmp"],
      "show_hidden": false
    }
  }
}
```

### File Output Mode (Large Trees)

```json
{
  "method": "tools/call",
  "params": {
    "name": "stump",
    "arguments": {
      "dir": "~/projects/large-repo",
      "output_file": "tree-output.json"
    }
  }
}
```

### With Performance Metrics

```json
{
  "method": "tools/call",
  "params": {
    "name": "stump",
    "arguments": {
      "dir": "~/projects/myapp",
      "performance": true
    }
  }
}
```

### Following Symlinks

```json
{
  "method": "tools/call",
  "params": {
    "name": "stump",
    "arguments": {
      "dir": "~/projects/app",
      "follow_symlinks": true
    }
  }
}
```

### Force Mode (Bypass Safety Checks)

```json
{
  "method": "tools/call",
  "params": {
    "name": "stump",
    "arguments": {
      "dir": "/home/user",
      "force": true,
      "depth": 2,
      "output_file": "home-tree.json"
    }
  }
}
```

## Configuration

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `dir` | string | (required) | Root directory path to scan |
| `depth` | integer | -1 | Maximum traversal depth (-1 = unlimited) |
| `include_ext` | array | [] | File extensions to include |
| `exclude_ext` | array | [] | File extensions to exclude |
| `exclude_patterns` | array | [] | Glob patterns to exclude |
| `show_hidden` | boolean | true | Show hidden files (starting with .) |
| `show_size` | boolean | true | Include file sizes in output |
| `show_modified` | boolean | false | Include modification timestamps |
| `follow_symlinks` | boolean | false | Follow symbolic links (with cycle detection) |
| `force` | boolean | false | Bypass safety warnings and continue on non-fatal errors |
| `performance` | boolean | false | Include performance metrics in output |
| `output_file` | string | null | Write to file instead of stdout |
| `token_limit` | integer | 10000 | Token limit for stdout mode (1000-100000, overrides env var) |

### Environment Variables

- `STUMP_TOKEN_LIMIT`: Default token limit for stdout mode (range: 1000-100000)
  - Can be overridden per-call with `token_limit` parameter
  - Values outside range are clamped to nearest valid value

## Output Format

### Compact JSON Structure

```json
{
  "root": "/path/to/dir",
  "depth": 3,
  "stats": {
    "dirs": 15,
    "files": 42,
    "filtered": 8,
    "symlinks": 2
  },
  "tree": [
    {"path": "src", "type": "d"},
    {"path": "src/main.zig", "type": "f", "size": 1024},
    {"path": "src/lib", "type": "d"},
    {"path": "src/lib/util.zig", "type": "f", "size": 512}
  ]
}
```

### Optional Fields

Fields only present when relevant:

- `symlinks_detected`: Array of detected symlinks (when `follow_symlinks: false`)
- `errors`: Array of non-fatal errors encountered during traversal
- `performance`: Detailed performance metrics (when `performance: true`)
- `_note`: "You asked for this" message (when `force: true`)

### Symlinks Detected

When symlinks are found and not followed:

```json
{
  "symlinks_detected": [
    {"path": "build", "target": "/tmp/build-cache"},
    {"path": "vendor/lib", "target": "../external/lib"}
  ]
}
```

### Error Array

Non-fatal errors collected during traversal:

```json
{
  "errors": [
    {"type": "permission_denied", "path": "private/data", "message": "Permission denied"},
    {"type": "invalid_symlink", "path": "broken", "target": "/nonexistent", "message": "Target does not exist"}
  ]
}
```

### Performance Metrics

When `performance: true`:

```json
{
  "performance": {
    "total_ms": 1234,
    "traversal_ms": 980,
    "filtering_ms": 45,
    "serialization_ms": 209,
    "peak_memory_bytes": 5242880,
    "final_memory_bytes": 3145728,
    "allocations": 42350,
    "stat_calls": 1523,
    "readdir_calls": 156,
    "symlink_resolutions": 8,
    "items_per_second": 1234,
    "bytes_per_second": 32145,
    "avg_time_per_item_us": 810,
    "filter_efficiency": 23.5
  }
}
```

## Error Handling

### Fatal Warnings (Block Execution)

Unless `force: true` is set:

1. **Large Directory Detection**: Refuses to traverse known large directories (`/`, `/usr`, `/home` on Unix; `C:\`, `C:\Windows`, `C:\Users` on Windows)
2. **Symlink Cycles**: When `follow_symlinks: true`, detects and blocks circular references
3. **Non-UTF8 Filenames**: Invalid UTF-8 encoding in filenames

### Non-Fatal Errors (Collected, Execution Continues)

Always collected in `errors` array:

1. **Permission Denied**: Cannot read directory or file
2. **Invalid Symlink**: Symlink points to non-existent path
3. **Path Too Long**: Exceeds OS path length limits
4. **Unreadable Files**: File exists but cannot be read

## Performance

### Benchmarks

Typical performance on modern hardware:

- **1,000 files**: < 100ms
- **10,000 files**: < 1s
- **100,000 files**: < 10s

Performance overhead when metrics tracking is disabled: < 1%

### Token Efficiency

Compared to standard `tree` command output:

- **Small projects** (100 files): 60% reduction
- **Medium projects** (1,000 files): 55% reduction
- **Large projects** (10,000+ files): 50%+ reduction

## Platform Support

- macOS (x86_64, aarch64)
- Linux (x86_64, aarch64)
- Windows (x86_64)

### Platform Notes

| Feature | macOS/Linux | Windows |
|---------|-------------|---------|
| Symlink detection | Full support | Full support |
| Symlink cycle detection | Device + inode pairs | File index (single volume) |
| Hidden file detection | Dot-prefix convention | Dot-prefix convention |
| Large directory safeguards | Unix system paths | Windows system paths |
| Temp file output | `/tmp` | `%TEMP%` / `%TMP%` |

## Development

### Project Structure

```
stump/
├── src/
│   ├── main.zig          # Entry point, CLI and MCP stdio handler
│   ├── mcp.zig           # MCP protocol handling
│   ├── lib.zig           # Library exports for testing
│   ├── config.zig        # Config resolution (token limits, env vars)
│   ├── types.zig         # All data structures
│   ├── tree.zig          # Core tree traversal logic
│   ├── filter.zig        # Filtering and pattern matching
│   ├── symlink.zig       # Symlink handling (detection + following)
│   ├── errors.zig        # Error types and handling
│   ├── safeguards.zig    # Large dir detection, UTF-8 validation
│   ├── output.zig        # JSON formatting
│   └── performance.zig   # Metrics tracking
├── test/
│   ├── unit/             # Unit tests for each module
│   ├── integration/      # End-to-end integration tests
│   └── fixtures/         # Test directories (basic, deep, wide, symlinks, utf8)
├── .github/workflows/    # CI/CD workflows
│   ├── test.yml          # Test on push/PR (Linux, macOS, Windows)
│   └── release.yml       # Build binaries on release
├── build.zig             # Zig build configuration
├── AGENTS.md             # AI agent development guide
├── README.md             # This file
└── LICENSE               # MIT license
```

### Contributing

When working on the codebase:

1. Follow Zig best practices (early returns, minimal abstraction, no OOP)
2. Maintain token efficiency in output format
3. Add tests for new features
4. Update documentation

## License

MIT License - see LICENSE file for details

## Authors

Built with AI-augmented concurrent development:

- **Initial Plan**: Co-authored by [@hegner123](https://github.com/hegner123) and Claude Sonnet 4.5
- **Implementation**: Concurrent task agents via [hq](https://github.com/hegner123/hq) coordination platform, Claude Sonnet 4.5
- **1st Round Bug Fixes**: Claude Sonnet 4.5 with documentation by [@hegner123](https://github.com/hegner123)
- **2nd Round Bug Fixes**: Claude Opus 4.5 with documentation by [@hegner123](https://github.com/hegner123)
- **Final Bug Fixes & Tests**: Claude Opus 4.5
- **Windows Compatibility**: Claude Opus 4.6
