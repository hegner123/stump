# Stump - MCP Tree Tool Plan

## Objective

Create an MCP server tool that provides tree-like directory visualization with compact, token-efficient, and easily parsable output optimized for LLM consumption.

## Key Design Decisions

**Output & Files:**
- UUID-based filename generation for file mode (prevents overwrites)
- JSON-only output format (no line-based alternative)
- File mode streams to disk with unique UUID filenames

**Error Handling:**
- Non-UTF8 filenames are **fatal errors** (can be bypassed with `force: true`)
- Human-readable, actionable error messages
- Clear distinction between fatal warnings and non-fatal errors

**Platform & Scope:**
- v1: Unix/Linux and macOS only
- v2: Windows support
- Gitignore support: deferred to v2 (not needed for v1)

**Defaults:**
- `show_hidden: true` - Show hidden files by default
- Token limit: 10,000 tokens (configurable 1k-100k)
- Safety-first: Large directories blocked unless forced

## Problem Statement

The standard `tree` CLI tool produces human-readable but token-heavy output. For LLM workflows, we need:
- Minimal tokens for large directory structures
- Structured, parsable format (JSON)
- Configurable depth and filtering
- Essential information without visual noise

## Output Format Design

### JSON Structure (Compact)
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
  ],
  "symlinks_detected": [
    {"path": "src/build", "target": "/tmp/build-output"},
    {"path": "vendor/lib", "target": "../external/lib"}
  ],
  "errors": [
    {"type": "permission_denied", "path": "private", "message": "Permission denied"}
  ]
}
```

**Optional fields:**
- `symlinks_detected` - only present when symlinks found and `follow_symlinks: false`
- `errors` - only present when non-fatal errors occurred during traversal
- `performance` - only present when `performance: true`
- `_note` - only present when `force: true`

**Decision:** JSON format for parseability and easy consumption by LLMs

### Output Modes

**1. Stdout Mode (Default)**
- Stores output internally during tree traversal
- Token consumption limit (configurable):
  - Default: 10,000 tokens (5% of 200k context window)
  - Configured via: `STUMP_TOKEN_LIMIT` env var OR `token_limit` parameter
  - Minimum: 1,000 tokens
  - Maximum: Claude's MCP tool input limit (~100,000 tokens)
  - Parameter overrides environment variable
  - Values outside range will be clamped
- If limit exceeded during build:
  - Clear memory immediately
  - Return error with message: "Token consumption would exceed limit (N tokens). Use 'output_file' parameter to save to file instead."
- Safeguard against accidentally consuming excessive context

**2. File Mode (output_file parameter)**
- Streams output directly to file with UUID-generated unique filename
- UUID incorporated into filename to prevent accidental overwrites
- Example: `/tmp/stump-<uuid>.json` or user-specified path with UUID inserted
- No token limit (writes entire tree to disk)
- Returns success message with actual file path and stats

## Core Features

### Must Have
1. **Recursive directory traversal** with configurable max depth
2. **Filtering**
   - File extensions (include/exclude)
   - Hidden files (show/hide)
   - Patterns (glob or exact match)
3. **Compact JSON output** - flat list format, no tree structure overhead
4. **Statistics** - file/dir counts, total size
5. **Symbolic link handling**
   - Default: detect but don't follow (prevent cycles)
   - Track symlinks in `symlinks_detected` array (path + target)
   - Optional: follow symlinks with `follow_symlinks` flag (with cycle detection)
6. **Error handling and safeguards**
   - Fatal warnings: large directory detection, symlink cycles (block execution unless `force: true`)
   - Non-fatal errors: permission denied, broken symlinks, path too long (collected in `errors` array)
   - `force` flag to bypass fatal warnings (adds `"_note": "You asked for this"` to output)
7. **Performance metrics** (optional)
   - Detailed timing, memory, and filesystem operation metrics
   - Enabled via `performance` flag
   - Minimal overhead when disabled (< 1%)

### Should Have (v1)
1. **Size information** - optional, file sizes
2. **Multiple root directories** - scan multiple dirs in one call
3. **Sort options** - name, size, type

### Future Features (v2+)
1. **Windows support** - Full Windows platform support
2. **Gitignore awareness** - respect .gitignore patterns
3. **File metadata** - modified time, permissions (optional)
4. **Content fingerprinting** - quick hash for change detection
5. **Diff mode** - compare two directory states

## MCP Integration

### Tool Definition
```json
{
  "name": "stump",
  "description": "Compact directory tree visualization optimized for LLM consumption",
  "inputSchema": {
    "type": "object",
    "properties": {
      "dir": {"type": "string", "description": "Root directory path"},
      "depth": {"type": "integer", "default": -1},
      "include_ext": {"type": "array", "items": {"type": "string"}},
      "exclude_ext": {"type": "array", "items": {"type": "string"}},
      "exclude_patterns": {"type": "array", "items": {"type": "string"}},
      "show_hidden": {"type": "boolean", "default": true},
      "show_size": {"type": "boolean", "default": true},
      "follow_symlinks": {"type": "boolean", "default": false, "description": "Follow symbolic links (with cycle detection)"},
      "force": {"type": "boolean", "default": false, "description": "Suppress warnings and continue on non-fatal errors"},
      "performance": {"type": "boolean", "default": false, "description": "Include performance metrics in output"},
      "output_file": {"type": "string", "description": "Write output to file instead of stdout"},
      "token_limit": {"type": "integer", "description": "Token limit for stdout mode (1000-100000). Overrides STUMP_TOKEN_LIMIT env var"}
    }
  }
}
```

### Transport
- **Stdio** - local execution, standard MCP pattern
- Written in Zig for performance and minimal dependencies

### Platform Support
**v1 (Initial Release):**
- **Unix/Linux** - Primary target
- **macOS** - Full support

**v2 (Future):**
- **Windows** - Full platform support

### MCP Error Responses
All error messages must be:
- **Human-readable** - Clear, actionable error messages
- **Contextual** - Include relevant paths, values, and recommendations
- **Consistent** - Follow standard error format with type, path, message fields
- **Helpful** - Suggest solutions or next steps

## Implementation Approach

### Language: Zig
**Rationale:**
- Performance critical for large directory trees
- Small binary, fast startup
- Good stdlib for filesystem operations
- Aligns with user's tool development preferences

### Project Structure
```
stump/
├── src/
│   ├── main.zig          # Entry point, MCP stdio handler
│   ├── config.zig        # Config resolution (token limits, flags)
│   ├── types.zig         # All data structures
│   ├── tree.zig          # Core tree traversal logic
│   ├── filter.zig        # Filtering and pattern matching
│   ├── symlink.zig       # Symlink handling (detection + following)
│   ├── errors.zig        # Error types and handling
│   ├── safeguards.zig    # Large dir detection, UTF-8 validation
│   ├── output.zig        # JSON formatting
│   └── performance.zig   # Metrics tracking
├── build.zig             # Zig build configuration
├── test/                 # Test fixtures and test files
└── README.md             # Usage and installation
```

### Core Algorithm
1. **Input validation** - check directory exists, parse parameters
2. **Initialize performance tracking** (if `performance: true`):
   - Start total timer
   - Initialize performance counters (syscall counts, memory tracking)
   - Set up high-resolution timers for each phase
3. **Large directory check**:
   - Resolve canonical path of input directory
   - Check against well-known large directories list
   - If match and `force: false`: return fatal error, ABORT execution
   - If match and `force: true`: continue (warning bypassed)
4. **Resolve token limit**:
   - Check `token_limit` parameter (highest priority)
   - Else check `STUMP_TOKEN_LIMIT` environment variable
   - Else use default: 10,000 tokens
   - Clamp to range: [1,000, 100,000] tokens
5. **Initialize state**:
   - Setup filters (extensions, patterns, hidden files)
   - Initialize symlink tracking (empty array for detected symlinks)
   - Initialize errors tracking (empty array for non-fatal errors)
   - If `follow_symlinks` enabled: initialize visited paths set for cycle detection
6. **Initialize output mode**:
   - If `output_file` set: open file handle for streaming
   - If stdout: initialize memory buffer with resolved token limit
7. **Traverse** - recursive walk with depth tracking (track time if performance enabled)
   - For each entry:
     - **Validate UTF-8 encoding** of filename:
       - Invalid UTF-8 and `force: false`: return fatal error, ABORT
       - Invalid UTF-8 and `force: true`: record in errors, skip entry
     - Check if it's a symlink:
       - If symlink and `follow_symlinks` is false: record in `symlinks_detected`, skip traversal
       - If symlink and `follow_symlinks` is true: resolve target, check for cycles
         - Cycle detected and `force: false`: return fatal error, ABORT
         - Cycle detected and `force: true`: record in errors, skip entry
         - No cycle: continue traversal
     - Increment syscall counters (stat_calls, readdir_calls, symlink_resolutions)
   - Handle non-fatal errors during traversal:
     - Permission denied: record in errors array, skip entry, continue
     - Invalid symlink: record in errors array, skip entry, continue
     - Path too long: record in errors array, skip entry, continue
     - Other errors: record in errors array, skip entry, continue
8. **Filter** - apply extension, pattern, hidden file rules (track time if performance enabled)
9. **Collect/Stream**:
   - File mode: stream entries directly to file
   - Stdout mode: accumulate in memory, check token count
   - If stdout exceeds limit: abort, clear memory, return error
10. **Format** - serialize to compact JSON (track time if performance enabled)
   - Include `symlinks_detected` array if any symlinks were found and not following
   - Include `errors` array if any non-fatal errors were collected
   - If `force: true`: include special message field: `"_note": "You asked for this"`
   - If `performance: true`: finalize metrics and include `performance` object
11. **Output**:
   - File mode: close file, return success message with path
   - Stdout mode: write complete JSON to stdout (MCP response)

### Symlink Handling

**Default behavior (follow_symlinks: false):**
- Detect symlinks during traversal
- Record each symlink: `{"path": "relative/path", "target": "/absolute/or/relative/target"}`
- Add to `symlinks_detected` array in output
- Do NOT follow symlink (skip directory/file traversal)
- Include symlink count in stats

**With follow_symlinks: true:**
- Resolve symlink target
- Use canonical path tracking to detect cycles
- Maintain a set of visited canonical paths (inode-based on Unix systems)
- If target already visited: skip (cycle detected), optionally log warning
- If target not visited: add to visited set, continue traversal
- Do NOT include `symlinks_detected` in output (they're being followed)

**Cycle detection approach:**
- Use filesystem inode numbers (Unix/Linux/macOS)
- Track (device_id, inode) pairs for visited directories
- Before entering directory, check if (dev, inode) already visited
- If visited: skip to prevent infinite loop

### Performance Metrics

**When `performance: true`:**
- Add `performance` object to output with detailed metrics
- Track metrics throughout traversal with minimal overhead
- Useful for debugging, optimization, and understanding tool behavior

**Metrics collected:**
1. **Execution time**
   - `total_ms` - Total execution time in milliseconds
   - `traversal_ms` - Time spent traversing filesystem
   - `filtering_ms` - Time spent applying filters
   - `serialization_ms` - Time spent serializing to JSON

2. **Memory consumption**
   - `peak_memory_bytes` - Peak memory usage during execution
   - `final_memory_bytes` - Memory usage at completion
   - `allocations` - Number of memory allocations

3. **Filesystem operations**
   - `stat_calls` - Number of stat() system calls
   - `readdir_calls` - Number of readdir() calls
   - `symlink_resolutions` - Number of readlink() calls

4. **Processing metrics**
   - `items_per_second` - Files+directories processed per second
   - `bytes_per_second` - Output bytes generated per second
   - `avg_time_per_item_us` - Average microseconds per file/directory

5. **Efficiency metrics**
   - `filter_efficiency` - Percentage of items filtered out
   - `cache_hits` - Cache hit count (if caching implemented)

**Performance output format:**
```json
{
  "root": "/path/to/dir",
  "stats": {...},
  "tree": [...],
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

**Implementation notes:**
- Performance tracking has minimal overhead (< 1% impact)
- Use high-resolution timers for accurate measurements
- Memory tracking via allocator instrumentation
- Only include `performance` object when `performance: true`

### Warning System and Force Flag

**Warning conditions (FATAL by default):**
1. **Large directory warning** - Traversing well-known massive directories
2. **Symlink cycle detected** - When `follow_symlinks: true`, cycle found
3. **Non-UTF8 filename** - Filename contains invalid UTF-8 sequences

**Non-fatal errors (never block execution):**
1. **Permission denied** - Cannot read directory or file (skip and continue)
2. **Invalid symlink target** - Symlink points to non-existent path (skip and continue)
3. **Path too deep** - Exceeds OS path length limits (skip and continue)
4. **Unreadable file** - File exists but cannot be read (skip and continue)

**Large directory detection:**
- Well-known massive directories that likely contain thousands/millions of files
- **Unix/Linux/macOS**: `/`, `/usr`, `/var`, `/home`, `/System`, `/Library`, `/Applications`
- **User directories**: `$HOME`, `~/`, user home directory root
- Check at start of traversal (before walking tree)
- **If detected and `force: false`**: ABORT with error message
- **If detected and `force: true`**: Continue execution (warning suppressed)

**Non-UTF8 filename handling:**
- All filenames must be valid UTF-8
- **Rationale**: Modern systems use UTF-8; invalid sequences indicate unusual files or legacy systems
- **Detection**: During traversal, validate filename encoding
- **If detected and `force: false`**: ABORT with fatal error, report problematic path
- **If detected and `force: true`**: Skip file, record in errors array, continue

**Default behavior (force: false):**
- Fatal warnings BLOCK execution and return error immediately
- Non-fatal errors are collected in `errors` array in output
- Continue processing through non-fatal errors
- Each error: `{"type": "permission_denied", "path": "foo/bar", "message": "Permission denied"}`

**With force: true:**
- Fatal warnings become non-blocking (execution continues)
- Non-fatal errors are still collected (not suppressed)
- Include `errors` array in output if any non-fatal errors occurred
- Used to bypass safety checks when user explicitly wants to proceed

**Fatal error responses:**

*Large directory detected:*
```json
{
  "error": "Large directory detected",
  "type": "large_directory",
  "path": "/home/user",
  "message": "Refusing to traverse large directory that may contain thousands of files. Recommendations: (1) Use 'depth' parameter to limit traversal, (2) Use filters to reduce scope, (3) Use 'output_file' to save results, or (4) Set 'force: true' to proceed anyway."
}
```

*Non-UTF8 filename:*
```json
{
  "error": "Invalid filename encoding",
  "type": "non_utf8_filename",
  "path": "/some/dir/file_with_bad_encoding",
  "message": "Encountered filename with invalid UTF-8 encoding. This may indicate a legacy file, corrupted filesystem, or unusual naming. Use 'force: true' to skip this file and continue."
}
```

**Non-fatal errors array (in successful output):**
```json
{
  "root": "/path/to/dir",
  "stats": {...},
  "tree": [...],
  "errors": [
    {"type": "permission_denied", "path": "private/data", "message": "Permission denied"},
    {"type": "invalid_symlink", "path": "broken", "target": "/nonexistent", "message": "Target does not exist"},
    {"type": "path_too_long", "path": "very/deep/...", "message": "Path exceeds OS limit"}
  ]
}
```

**With force: true (safeguards disabled):**
```json
{
  "root": "/home/user",
  "stats": {...},
  "tree": [...],
  "_note": "You asked for this"
}
```

### Token Counting
**Estimation approach:**
- Assume ~4 characters per token (rough approximation)
- Track byte count of accumulated JSON output
- Limit calculation: `token_limit × 4 chars/token = max_bytes`
  - Minimum: 1,000 tokens × 4 = 4,000 bytes
  - Default: 10,000 tokens × 4 = 40,000 bytes
  - Example: 20,000 tokens × 4 = 80,000 bytes
  - Maximum: 100,000 tokens × 4 = 400,000 bytes
- Check limit after each entry added to tree array
- On exceed: clear buffer, return error immediately

**Limit resolution order:**
1. `token_limit` parameter (highest priority)
2. `STUMP_TOKEN_LIMIT` environment variable
3. Default: 10,000 tokens
4. Clamp to range: [1,000, 100,000] tokens

**Error message format:**
```json
{
  "error": "Token limit exceeded",
  "message": "Tree output would exceed token limit (N tokens, ~M bytes). Use 'output_file' parameter to save to file instead, or increase 'token_limit' (range: 1000-100000).",
  "stats": {
    "dirs": 150,
    "files": 420,
    "aborted_at": 40000,
    "token_limit": 10000
  }
}
```

## Performance Considerations

1. **Streaming vs Collection**
   - File mode: Stream directly to disk (low memory, handles unlimited size)
   - Stdout mode: Collect in memory (enables token counting and limit enforcement)
   - **Decision:** Hybrid approach based on output mode

2. **Parallel Traversal**
   - Potentially traverse subdirectories in parallel
   - **Decision:** Start single-threaded, optimize later if needed

3. **Caching**
   - Cache stat() calls where possible (future optimization)

## Testing Strategy

### Unit Tests
- Filter logic (extensions, patterns, hidden files)
- JSON output formatting
- Path normalization
- Token counting accuracy (byte-to-token estimation)
- Token limit resolution (parameter > env var > default)
- Token limit clamping (values < 1k → 1k, values > 100k → 100k)
- Symlink detection and recording (follow_symlinks: false)
- Symlink cycle detection (follow_symlinks: true)
- Non-fatal error collection (permission errors, broken symlinks)
- Fatal error handling (large directories, symlink cycles)
- Force flag behavior (fatal errors become non-blocking)
- Large directory detection (canonical path matching)
- "_note" field present when force: true
- Performance metrics collection and accuracy
- Performance object only present when performance: true

### Integration Tests
- Full tree traversal on test fixtures
- MCP stdio protocol compliance
- Large directory performance benchmarks
- Token limit enforcement with different limits
- Token limit via environment variable
- Token limit via parameter (overrides env var)
- File mode streaming and output verification
- Symlink detection (verify symlinks_detected array)
- Symlink following (verify no cycles, correct traversal)
- Symlink cycle prevention (verify cycle detection works)
- Performance metrics accuracy (compare against known baseline)
- Performance overhead measurement (< 1% impact when disabled)

### Test Fixtures
```
test/fixtures/
├── basic/              # Simple dir structure
├── deep/               # Deep nesting (10+ levels)
├── wide/               # Many files in single dir
├── mixed/              # Various file types
├── symlinks/           # With symbolic links (file and dir)
├── symlink-cycle/      # Symlinks that create cycles
├── utf8/               # Various UTF-8 filenames (edge cases)
├── non-utf8/           # Invalid UTF-8 filenames (for testing fatal error)
└── large/              # Exceeds 10k token limit (for testing token limit enforcement)
```

## Success Criteria

1. **Token Efficiency** - 50%+ reduction vs standard tree output for typical projects
2. **Performance** - <100ms for 1000 files, <1s for 10,000 files
3. **Accuracy** - Correctly applies filters and handles edge cases
4. **Reliability** - Handles edge cases (symlinks, permissions errors, deep nesting, UTF-8 validation)
5. **MCP Compliance** - Works with Claude Code and other MCP clients
6. **Token Limit Enforcement** - Correctly detects and aborts when stdout output would exceed configured token limit
7. **File Mode** - Successfully writes trees of any size to disk without memory issues
8. **Symlink Handling** - Correctly detects and reports symlinks by default, follows with cycle detection when enabled
9. **Safety Safeguards** - Blocks large directory traversal by default, can be overridden with force flag
10. **Error Reporting** - Distinguishes fatal warnings from non-fatal errors, collects and reports appropriately
11. **Performance Metrics** - Accurate tracking with < 1% overhead when disabled, comprehensive metrics when enabled

## Installation & Usage

### Build
```bash
zig build -Doptimize=ReleaseFast
```

### MCP Server Config

**Basic installation (default 10k token limit):**
```bash
claude mcp add --transport stdio stump -- /path/to/stump
```

**With custom token limit via environment variable:**
```bash
# Set token limit to 20k tokens (will be applied to all invocations)
claude mcp add --transport stdio stump -- env STUMP_TOKEN_LIMIT=20000 /path/to/stump
```

**Configuration notes:**
- `STUMP_TOKEN_LIMIT` env var sets default limit for all calls
- `token_limit` parameter can override per-call
- Valid range: 1,000 to 100,000 tokens
- Values outside range will be clamped to nearest valid value

### Example Calls

**Stdout mode (default 10k token limit):**
```json
{
  "method": "tools/call",
  "params": {
    "name": "stump",
    "arguments": {
      "dir": "~/projects/myapp",
      "depth": 3,
      "exclude_ext": ["log", "tmp"]
    }
  }
}
```

**Stdout mode with custom token limit:**
```json
{
  "method": "tools/call",
  "params": {
    "name": "stump",
    "arguments": {
      "dir": "~/projects/medium-repo",
      "depth": 5,
      "token_limit": 25000
    }
  }
}
```

**File mode (for large trees):**
```json
{
  "method": "tools/call",
  "params": {
    "name": "stump",
    "arguments": {
      "dir": "~/projects/large-repo",
      "output_file": "/tmp/tree-output.json"
    }
  }
}
```
Response:
```json
{
  "success": true,
  "message": "Tree written to /tmp/tree-output.json",
  "stats": {
    "dirs": 450,
    "files": 2340,
    "size_bytes": 125000
  }
}
```

**With symlink detection (default):**
```json
{
  "method": "tools/call",
  "params": {
    "name": "stump",
    "arguments": {
      "dir": "~/projects/app",
      "follow_symlinks": false
    }
  }
}
```
Response includes `symlinks_detected` array:
```json
{
  "root": "/home/user/projects/app",
  "depth": -1,
  "stats": {
    "dirs": 10,
    "files": 25,
    "symlinks": 2
  },
  "tree": [...],
  "symlinks_detected": [
    {"path": "build", "target": "/tmp/build-cache"},
    {"path": "vendor/lib", "target": "../external/lib"}
  ]
}
```

**Following symlinks:**
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
Response traverses symlink targets (no `symlinks_detected` array)

**Force mode (bypass safeguards for large directory):**
```json
{
  "method": "tools/call",
  "params": {
    "name": "stump",
    "arguments": {
      "dir": "/home/user",
      "force": true,
      "depth": 2,
      "output_file": "/tmp/home-tree.json"
    }
  }
}
```
Response includes `"_note": "You asked for this"` and bypasses large directory fatal error.

**Performance metrics enabled:**
```json
{
  "method": "tools/call",
  "params": {
    "name": "stump",
    "arguments": {
      "dir": "~/projects/myapp",
      "performance": true,
      "depth": 3
    }
  }
}
```
Response includes detailed `performance` object with timing, memory, and filesystem operation metrics.

## Open Questions

1. Should size be in bytes or human-readable (KB/MB)?
2. Include file count per directory in output?

## Next Steps

1. Initialize Zig project with build.zig
2. Implement core tree traversal without filtering
3. Add JSON output formatting
4. Implement large directory detection and fatal error handling
5. Implement error tracking system (fatal vs non-fatal)
6. Implement symlink detection and tracking
7. Implement symlink following with cycle detection
8. Implement token counting and stdout limit enforcement
9. Implement file mode output streaming
10. Implement basic filtering (extensions, hidden files)
11. Implement force flag and "_note" field
12. Implement performance tracking system
    - High-resolution timers for phases
    - Memory tracking via allocator instrumentation
    - Syscall counters
    - Metric calculation and formatting
13. Create MCP stdio wrapper
14. Write tests (including error handling, token limit, symlink, UTF-8 validation, and performance tests)
15. Benchmark and optimize
16. Documentation and examples
