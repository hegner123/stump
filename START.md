# Stump - MCP Tree Tool

Token-efficient directory tree visualization MCP server written in Zig.

## Quick Overview

**What:** MCP server tool providing compact, JSON-formatted directory trees optimized for LLM consumption

**Why:** Standard `tree` command is token-heavy. Stump reduces token usage by 50%+ with structured JSON output

**Language:** Zig (performance-critical, small binary, fast startup)

**Output:** Compact JSON with configurable token limits, file streaming for large trees, symlink detection, error handling

## Project Status

**Current Phase:** Planning complete, ready for implementation

**Development Model:** Multi-agent concurrent development using git worktrees

## Key Paths

### Documentation
- `PLAN.md` - Main project specification and design decisions
- `CONCURRENT-PLAN.md` - Multi-agent development plan with dependency graph
- `AGENT-QUICKSTART.md` - Quick start guide for agents working on specific tasks
- `SETUP-CHECKLIST.md` - Setup verification checklist before starting development
- `START.md` (this file) - Project onboarding and orientation

### Source Code (to be created)
- `src/main.zig` - MCP stdio handler and orchestration
- `src/types.zig` - Core data structures (TreeEntry, Stats, Config)
- `src/config.zig` - Configuration resolution (token limits, env vars)
- `src/errors.zig` - Error types and formatting
- `src/tree.zig` - Core recursive traversal logic
- `src/filter.zig` - Extension and pattern filtering
- `src/symlink.zig` - Symlink detection and cycle prevention
- `src/safeguards.zig` - Large directory detection, UTF-8 validation
- `src/output.zig` - JSON serialization and file streaming
- `src/performance.zig` - Optional performance metrics tracking

### Build & Tests
- `build.zig` - Zig build configuration
- `test/unit/` - Unit tests for individual modules
- `test/integration/` - End-to-end MCP protocol tests
- `test/fixtures/` - Test directory structures (basic, deep, wide, symlinks, etc.)

### Scripts
- `scripts/worktree-helper.sh` - Automation for concurrent development workflow

### Reference Materials
- `ai/zig-reference/` - Zig standard library references for filesystem operations

## Quick Start Commands

### For Single-Agent Development

```bash
# Initialize Zig project
zig init-exe

# Build
zig build -Doptimize=ReleaseFast

# Run tests
zig build test

# Install as MCP server
claude mcp add --transport stdio stump -- /path/to/stump
```

### For Multi-Agent Concurrent Development

**Coordinator setup:**
```bash
# 1. Create worktrees (see CONCURRENT-PLAN.md for commands)
git worktree add -b step1a/core-add-types ../stump-step1a-core-add-types
# ... (create all 14 worktrees)

# 2. Create MCP project
Use mcp__concurrent-agent-mcp__create_project:
- name: "stump"
- base_commit: <git rev-parse HEAD>
- steps: [array of 14 step definitions from CONCURRENT-PLAN.md]

# 3. Verify setup
Use mcp__concurrent-agent-mcp__get_project with name: "stump"
```

**Agent workflow:**
```
# Check available work
Use mcp__concurrent-agent-mcp__get_available_steps with project: "stump"

# Claim next available step
Use mcp__concurrent-agent-mcp__claim_step with:
- project: "stump"
- agent_id: "agent-<name>"

# Start the step
Use mcp__concurrent-agent-mcp__start_step with:
- step_id: <from claim>
- worktree: "../stump-<branch>"

# Navigate to worktree
cd ../stump-<branch-name>

# Work on implementation with periodic heartbeats
git add . && git commit -m "message" && git push

Use mcp__concurrent-agent-mcp__heartbeat every 30-60 sec:
- step_id: <your step>
- agent_id: "agent-<name>"

# Mark complete
Use mcp__concurrent-agent-mcp__complete_step with:
- step_id: <your step>
- commit_hash: <git rev-parse HEAD>
- files_modified: ["src/file.zig"]

# Check overall status
Use mcp__concurrent-agent-mcp__get_project with name: "stump"
Use mcp__concurrent-agent-mcp__get_metrics with project: "stump"

# Coordinator: Merge all completed steps (when all done)
# See CONCURRENT-PLAN.md for merge order

# Cleanup after successful merge
# Remove worktrees, delete branches (see CONCURRENT-PLAN.md)
```

## Architecture Overview

### Core Design Principles

1. **Token Efficiency First** - Flat JSON array format, minimal overhead
2. **Safety by Default** - Large directory detection, UTF-8 validation, token limits
3. **Flexible Output** - Stdout mode (with limits) or file streaming (unlimited)
4. **Comprehensive Error Handling** - Fatal errors block execution, non-fatal errors collected

### Data Flow

```
Input Parameters
    ↓
Config Resolution (token limits, env vars)
    ↓
Safety Checks (large dir detection, UTF-8 validation)
    ↓
Recursive Traversal (with filters, symlink handling)
    ↓
Entry Collection (memory or file stream)
    ↓
JSON Serialization
    ↓
Output (stdout or file)
```

### Key Features

**Output Modes:**
- Stdout mode: Default, token-limited (1k-100k configurable, default 10k)
- File mode: Streams to disk with UUID filenames, no limits

**Filtering:**
- File extensions (include/exclude)
- Hidden files (show/hide, default: show)
- Glob patterns
- Depth limiting

**Symlink Handling:**
- Default: Detect but don't follow (track in `symlinks_detected` array)
- Optional: Follow with cycle detection (inode-based)

**Error System:**
- Fatal errors: Large directories, non-UTF8 filenames, symlink cycles (block unless `force: true`)
- Non-fatal errors: Permission denied, broken symlinks (collect in `errors` array, continue)

**Performance Metrics (optional):**
- Execution timing (traversal, filtering, serialization)
- Memory consumption (peak, final, allocations)
- Filesystem operations (stat calls, readdir calls)
- Processing metrics (items/sec, bytes/sec)

### Module Dependencies

```
Foundation (no dependencies):
- types.zig
- config.zig
- errors.zig
- performance.zig

Subsystems (depend on foundation):
- filter.zig      → types, errors
- symlink.zig     → types, errors
- safeguards.zig  → types, errors

Core (depends on foundation + subsystems):
- tree.zig        → types, errors, filter, symlink, safeguards

Output (depends on foundation):
- output.zig      → types, performance

Main (depends on everything):
- main.zig        → ALL modules
```

## Development Approach

### Single-Agent Path

1. Read PLAN.md fully
2. Implement modules in dependency order (types → config → errors → etc.)
3. Write tests as you go
4. Build and verify incrementally

### Multi-Agent Path (Recommended)

1. **Coordinator:** Run setup checklist (SETUP-CHECKLIST.md)
   - Create worktrees for all 14 steps
   - Use `mcp__concurrent-agent-mcp__create_project` to initialize project
   - Verify setup with `mcp__concurrent-agent-mcp__get_project`

2. **All Agents:** Read AGENT-QUICKSTART.md
   - Ensure MCP concurrent-agent access
   - Understand heartbeat requirement (every 30-60 sec)

3. **Agents dynamically claim work:**
   - Use `get_available_steps` to see ready work
   - Use `claim_step` to atomically claim next available step
   - MCP system automatically manages dependencies
   - Agents can work in parallel without coordination overhead

4. **Expected wave pattern (with automatic dependency resolution):**
   - Wave 1: Steps 1-4, 11 (no dependencies)
   - Wave 2: Steps 5-7 (after steps 1,3 complete)
   - Wave 3: Step 8 (after steps 1,3,5,6,7 complete)
   - Wave 4: Steps 9-10 (staggered dependencies)
   - Wave 5: Steps 12-14 (tests after implementation)

5. **Coordinator:** Merge in exact step order, verify tests, cleanup

## Important Notes

### Platform Support
- **v1:** Unix/Linux and macOS only
- **v2 (future):** Windows support
- Gitignore support deferred to v2

### Configuration
- Token limit: Environment variable `STUMP_TOKEN_LIMIT` or parameter `token_limit`
- Default: 10,000 tokens (~40KB)
- Range: 1,000 - 100,000 tokens

### Well-Known Large Directories (Blocked by Default)
- `/`, `/usr`, `/var`, `/home`, `/System`, `/Library`, `/Applications`
- User home directory root
- Use `force: true` to bypass

### Token Estimation
- Rough approximation: 4 characters per token
- Byte limit = token_limit × 4
- Checked after each entry added during traversal

## Onboarding

For agents joining this project:

1. **Read documentation in order:**
   - START.md (this file) - Project overview and orientation
   - PLAN.md - Complete specification and design decisions
   - CONCURRENT-PLAN.md - Multi-agent development plan (if doing concurrent dev)
   - AGENT-QUICKSTART.md - Quick reference for agent workflow (if doing concurrent dev)

2. **Memorize key project structure:**
   - Documentation: PLAN.md, CONCURRENT-PLAN.md, AGENT-QUICKSTART.md, SETUP-CHECKLIST.md
   - Source (to be created): src/*.zig modules
   - Tests (to be created): test/unit/, test/integration/, test/fixtures/
   - Scripts: scripts/worktree-helper.sh
   - Reference: ai/zig-reference/

3. **Understand the development model:**
   - Multi-agent concurrent development using git worktrees + MCP coordination
   - 14 parallel work streams with automatic dependency tracking
   - Coordination via MCP concurrent-agent server (SQLite-backed, atomic operations)
   - Strict file ownership rules (no conflicts)

4. **For concurrent development, verify setup:**
   - Check if MCP project exists: Use `mcp__concurrent-agent-mcp__get_project` with name: "stump"
   - Check if worktrees created: `git worktree list`
   - If not: Coordinator needs to follow SETUP-CHECKLIST.md

5. **Choose your workflow:**
   - Single-agent: Implement modules in dependency order
   - Multi-agent: Use MCP `claim_step` to atomically claim work, send heartbeats while working

6. **Key principles to remember:**
   - Token efficiency is the primary goal
   - Safety by default (can be bypassed with `force: true`)
   - No regex (use exact string matching for filenames)
   - Early returns, minimal abstraction (Zig best practices)
   - Human-readable error messages

7. **Before writing code:**
   - Read the relevant section in PLAN.md for your module
   - Understand the module's dependencies
   - Review the expected data structures (types.zig interface)
   - Check test fixtures to understand expected behavior

## Success Criteria

The project is complete when:

1. Token efficiency: 50%+ reduction vs standard tree output
2. Performance: <100ms for 1000 files, <1s for 10,000 files
3. All features implemented per PLAN.md
4. Token limit enforcement working correctly
5. Symlink handling with cycle detection working
6. Safety safeguards functioning (large dir, UTF-8 validation)
7. Error system distinguishing fatal vs non-fatal errors
8. Performance metrics accurate with <1% overhead when disabled
9. MCP protocol compliance verified
10. All tests passing
11. Can be installed and used as MCP server with Claude Code

## Questions?

- **Project specification:** See PLAN.md
- **Concurrent development:** See CONCURRENT-PLAN.md
- **Quick workflow reference:** See AGENT-QUICKSTART.md
- **Setup verification:** See SETUP-CHECKLIST.md
- **MCP project status:** Use `mcp__concurrent-agent-mcp__get_project` with name: "stump"
- **MCP metrics:** Use `mcp__concurrent-agent-mcp__get_metrics` with project: "stump"

## Links & Resources

- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [MCP Specification](https://spec.modelcontextprotocol.io/)
- [Claude Code MCP Servers](https://github.com/anthropics/claude-code)

## Getting Started Now

**If you're the coordinator setting up:**
1. Follow SETUP-CHECKLIST.md phases 1-8
2. Create worktrees for all 14 steps
3. Use `mcp__concurrent-agent-mcp__create_project` to initialize
4. Verify with `mcp__concurrent-agent-mcp__get_project`
5. Brief all agents on MCP workflow

**If you're an agent joining:**
1. Verify MCP access: `mcp__concurrent-agent-mcp__list_projects`
2. Check if project exists: `mcp__concurrent-agent-mcp__get_project` with name: "stump"
3. See available work: `mcp__concurrent-agent-mcp__get_available_steps` with project: "stump"
4. Claim next step: `mcp__concurrent-agent-mcp__claim_step` with project: "stump", agent_id: "agent-<name>"
5. Start working and send heartbeats every 30-60 seconds

**Good luck building Stump!**
