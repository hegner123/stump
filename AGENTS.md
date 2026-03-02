# AGENTS.md

## Project Overview

**Stump** is a high-performance MCP (Model Context Protocol) server tool that provides compact, token-efficient directory tree visualization optimized for LLM consumption. Written in **Zig 0.15.2**, it runs as either a CLI tool or an MCP stdio server.

- **Language**: Zig 0.15.2+
- **Platforms**: macOS, Linux (no Windows support)
- **License**: MIT
- **Repository**: https://github.com/hegner123/stump

## Commands

### Build

```bash
zig build                        # Development build
zig build release-fast           # Optimized release build (recommended for production)
zig build release-safe           # Release with safety checks
zig build release-small          # Minimal binary size
```

Binary output: `zig-out/bin/stump`

### Test

```bash
zig build test                   # Run all tests (unit + integration)
zig build test-unit              # Unit tests only
zig build test-integration       # Integration tests only
```

### Other

```bash
zig build run                    # Build and run the MCP server
zig build run -- <args>          # Build and run in CLI mode with arguments
zig build docs                   # Generate documentation from doc comments
make install                     # Build release-fast + copy to /usr/local/bin/
make clean                       # Remove zig-out/ and .zig-cache/
```

### MCP Installation

```bash
claude mcp add --transport stdio stump -- /path/to/zig-out/bin/stump
```

## Project Structure

```
src/
├── main.zig          # Entry point: CLI arg parsing, MCP stdio loop, request routing
├── lib.zig           # Re-exports all modules for test access (stump_lib_module)
├── mcp.zig           # MCP/JSON-RPC 2.0 protocol: state machine, response builders
├── types.zig         # All shared data structures (Config, TreeEntry, Stats, etc.)
├── config.zig        # Token limit resolution, large-directory path list, constants
├── tree.zig          # Core recursive traversal engine (buildTree entry point)
├── filter.zig        # Extension/pattern/hidden-file filtering with glob matching
├── symlink.zig       # Symlink detection, resolution, and cycle prevention
├── safeguards.zig    # Pre-traversal validation (large dir check, UTF-8 validation)
├── errors.zig        # Error factory functions for typed error entries
├── output.zig        # JSON serialization (manual, not std.json), file/stdout output
└── performance.zig   # Optional timing/memory/filesystem metrics tracking
test/
├── unit/             # Per-module unit tests
│   ├── all_tests.zig # Aggregator that imports all unit test modules
│   ├── config_test.zig
│   ├── errors_test.zig
│   ├── filter_test.zig
│   ├── mcp_test.zig
│   ├── output_test.zig
│   ├── performance_test.zig
│   ├── safeguards_test.zig
│   ├── symlink_test.zig
│   └── types_test.zig
├── integration/      # End-to-end integration tests
│   ├── all_tests.zig
│   └── basic_integration_test.zig
└── fixtures/         # Test directories (basic, deep, wide, symlinks, utf8, large, etc.)
planning/             # Development planning docs (historical, not active)
.github/workflows/    # CI: test.yml (build + unit + integration), release.yml
build.zig             # Zig build configuration with all steps
Makefile              # Convenience wrappers (build, release, install, clean, test)
```

## Module Dependency Graph

```
Foundation (no dependencies):
  types.zig, config.zig, errors.zig, performance.zig

Subsystems (depend on foundation):
  filter.zig      → types, errors
  symlink.zig     → types, errors
  safeguards.zig  → types, errors, config

Core (depends on foundation + subsystems):
  tree.zig        → types, filter, symlink, safeguards, errors

Output (depends on foundation):
  output.zig      → types, performance

Protocol (standalone):
  mcp.zig         → std only

Main (depends on everything):
  main.zig        → all modules

Library (re-export hub):
  lib.zig         → re-exports all modules as `pub const`
```

## Architecture & Data Flow

```
CLI args / MCP JSON-RPC request
    ↓
Config parsing (main.parseCliArgs or main.parseConfig)
    ↓
Token limit resolution (config.resolveTokenLimit: param > env > default)
    ↓
tree.buildTree:
    ├── safeguards.checkLargeDirectory (fatal if matched, unless force=true)
    ├── filter.FilterContext.init (snapshot filter rules from Config)
    └── traverseDirectory (recursive):
        ├── safeguards.isValidUtf8 (per-entry filename check)
        ├── symlink handling (detect-and-skip or follow-with-cycle-check)
        ├── filter.shouldInclude (hidden, extension, glob pattern)
        └── addFileEntry / addDirectoryEntry (with token limit check)
    ↓
main.buildOutputData (borrows slices from TraversalState)
    ↓
output.serializeToStdout / output.serializeToFile (manual JSON serialization)
    ↓
MCP content wrapper (mcp.buildToolContent) or direct stdout
```

## Dual-Mode Operation

The binary detects its mode at startup:
- **CLI mode**: When command-line arguments are present. Parses args, runs tree, prints JSON to stdout, exits.
- **MCP mode**: When no arguments are present. Enters JSON-RPC 2.0 stdio loop reading from stdin, writing to stdout.

Both modes share the same core pipeline: `Config → tree.buildTree → output serialization`.

## Code Conventions & Patterns

### Zig Style

- **Early returns** over nested conditionals
- **Minimal abstraction** — no OOP, no inheritance patterns
- **Explicit error handling** — `errdefer` for cleanup, error unions throughout
- **Manual memory management** — every allocation has a matching `deinit` or `free`
- All allocations use the passed `std.mem.Allocator` (never global state)
- `GeneralPurposeAllocator` in main, `std.testing.allocator` in tests

### Naming

- Files: `snake_case.zig`
- Types/structs: `PascalCase` (e.g., `TreeEntry`, `FilterContext`, `PerformanceTracker`)
- Functions: `camelCase` (e.g., `buildTree`, `shouldInclude`, `resolveTokenLimit`)
- Constants: `SCREAMING_SNAKE_CASE` (e.g., `LARGE_DIRECTORIES`, `MAX_TOKEN_LIMIT`)
- Enum variants: `snake_case` (e.g., `.large_directory`, `.permission_denied`)

### Error Handling Pattern

The codebase distinguishes **fatal** vs **non-fatal** errors:
- **Fatal errors** (large_directory, non_utf8_filename, symlink_cycle) halt execution unless `force: true`
- **Non-fatal errors** (permission_denied, invalid_symlink, path_too_long, unreadable_file) are collected in `TraversalState.errors` and included in the JSON output

Fatal errors are represented by `types.FatalError` structs. Non-fatal errors use `types.ErrorEntry`. Both are created by factory functions in `errors.zig`.

### Memory Ownership

- Structs that own allocated memory have `deinit(allocator)` methods
- `errdefer` is used consistently for cleanup on error paths
- `TraversalState` owns tree entries, symlinks, and errors — `deinit` frees them all
- `OutputData` in `main.buildOutputData` *borrows* slices from `TraversalState` (does not copy)
- String fields in error/symlink entries are duplicated via `allocator.dupe` for independent ownership

### JSON Serialization

JSON is constructed **manually** using `std.ArrayList(u8)` writers — not `std.json.stringify`. This gives precise control over:
- Field ordering
- Optional field omission (null fields are not emitted)
- Compact output (no whitespace)
- JSON string escaping (via `writeJsonEscapedString` / `writeJsonString`)

### MCP Protocol

- JSON-RPC 2.0 over stdio (newline-delimited messages)
- Protocol state machine: `uninitialized → initializing → ready`
- Single tool: `"stump"` — any other tool name returns `TOOL_NOT_FOUND`
- Supports request cancellation via `notifications/cancelled`
- MCP version: `2024-11-05`

### Token Limit System

- Rough approximation: **4 characters = 1 token**
- `resolved_byte_limit = resolved_token_limit × 4`
- Three-tier priority: CLI/MCP parameter > `STUMP_TOKEN_LIMIT` env var > default (10,000)
- Range: 1,000–100,000 tokens (clamped)
- Checked during traversal (estimated) and after serialization (exact)

## Testing

### Test Organization

- **Unit tests** live in `test/unit/` and import modules via `@import("stump")` (the library module)
- **Integration tests** live in `test/integration/` and also import via `@import("stump")`
- **Inline tests** exist in some source files (`config.zig`, `filter.zig`, `output.zig`, `safeguards.zig`) — these run with `zig build test-unit` via the module dependency
- Test aggregators: `test/unit/all_tests.zig` and `test/integration/all_tests.zig` import all test files via `_ = @import("..._test.zig")`

### Test Fixtures

Located in `test/fixtures/`:
- `basic/` — simple directory with hidden files and subdirs
- `deep/` — deeply nested directories (4+ levels)
- `wide/` — 100 files in a single directory
- `large/` — 50 dirs × 20 files (1,000+ entries)
- `symlinks/` — regular file links, directory links
- `symlink-cycle/` — circular symlink references
- `utf8/` — filenames in various scripts (CJK, Cyrillic, Arabic, Hebrew, emoji)
- `non-utf8/` — placeholder for invalid encoding tests
- `mixed/` — various file types (json, png, tar.gz, sh, txt)

### Test Patterns

```zig
const std = @import("std");
const testing = std.testing;
const stump = @import("stump");       // Access via library module
const config = stump.config;          // Then drill into submodule

test "descriptive test name" {
    const allocator = testing.allocator;   // Use testing allocator (leak-detecting)
    // ... test body ...
    try testing.expectEqual(expected, actual);
    try testing.expectEqualStrings("expected", actual_str);
    try testing.expect(boolean_condition);
}
```

### Adding Tests

1. Create `test/unit/<module>_test.zig`
2. Import via `@import("stump").<module>`
3. Add `_ = @import("<module>_test.zig");` to `test/unit/all_tests.zig`
4. Run with `zig build test-unit`

## Gotchas & Non-Obvious Patterns

### `lib.zig` is the test entry point, not `main.zig`

Tests import the `"stump"` module which resolves to `src/lib.zig`. This re-exports all internal modules. The main executable imports modules directly — `lib.zig` is only for test access.

### `OutputData` borrows from `TraversalState`

`main.buildOutputData` does **not** copy tree entries, symlinks, or errors — it takes slice references. The `TraversalState.deinit()` must be called **after** `OutputData` is done being used. The `defer` ordering in `executeStump` is critical.

### Manual JSON serialization

Don't use `std.json.stringify` for output. The codebase manually writes JSON for size/ordering control. Follow the pattern in `output.writeJson` and `mcp.buildToolContent`.

### Token limit checked twice

Token limits are estimated during traversal (heuristic: path length + 50 bytes overhead per entry) and checked again after full serialization. The traversal check can abort early, the serialization check catches oversize output.

### `getExtension` returns everything after the *last* dot

`filter.getExtension("archive.tar.gz")` returns `"tar.gz"`, not `"gz"`. This matters for multi-dotted filenames.

### `force: true` converts fatal errors to non-fatal

When force mode is on, large directory detection, UTF-8 errors, and symlink cycles become non-fatal — they're recorded in the errors array instead of halting execution.

### Symlink handling has two distinct modes

- `follow_symlinks: false` (default): symlinks are detected, recorded in `symlinks_detected` array, and skipped
- `follow_symlinks: true`: symlinks are resolved and traversed with device/inode cycle detection via `TraversalState.visited_paths`

### CI runs on both Ubuntu and macOS

The test workflow (`test.yml`) uses a matrix of `[ubuntu-latest, macos-latest]`. Tests should work on both platforms. The release workflow builds for 4 targets: x86_64-linux, aarch64-linux, x86_64-macos, aarch64-macos.

### Some source modules have inline tests

`config.zig`, `filter.zig`, `output.zig`, and `safeguards.zig` contain `test` blocks at the bottom of the file. These are discovered through the unit test module dependency chain.

### `std.ArrayList` initialization

ArrayLists are initialized without an allocator: `std.ArrayList(T){}`. The allocator is passed to each method call (`.append(allocator, item)`, `.deinit(allocator)`). This is the Zig 0.15+ pattern.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `STUMP_TOKEN_LIMIT` | Default token limit for stdout mode (1000-100000) | 10000 |

## Key Constants

| Constant | Value | Location |
|----------|-------|----------|
| `MIN_TOKEN_LIMIT` | 1,000 | `config.zig` |
| `MAX_TOKEN_LIMIT` | 100,000 | `config.zig` |
| `DEFAULT_TOKEN_LIMIT` | 10,000 | `config.zig` |
| `LARGE_DIRECTORIES` | /, /usr, /var, /home, /System, etc. | `config.zig` |
| Chars per token | 4 | `config.tokenLimitToBytes` |
