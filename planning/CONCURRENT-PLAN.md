# Stump - Concurrent Development Plan

Multi-agent worktree-based development plan for parallel implementation.

## Overview

**Agents:** 4-5 Claude instances working simultaneously
**Method:** Git worktrees with isolated branches
**Tracking:** MCP concurrent-agent server (SQLite-backed, atomic operations)
**Timeline:** All agents start simultaneously, merge in step order

## Dependency Analysis

### Independent Modules (Parallel Safe)
- **types.zig** - Data structures (no dependencies)
- **config.zig** - Configuration resolution (no dependencies)
- **errors.zig** - Error types (no dependencies)
- **performance.zig** - Metrics tracking (uses types.zig)
- **filter.zig** - Filtering logic (uses types.zig)
- **symlink.zig** - Symlink handling (uses types.zig, errors.zig)
- **safeguards.zig** - Safety checks (uses types.zig, errors.zig)

### Dependent Modules (Sequential Requirements)
- **tree.zig** - DEPENDS ON: types.zig, errors.zig, symlink.zig, safeguards.zig, filter.zig
- **output.zig** - DEPENDS ON: types.zig, performance.zig
- **main.zig** - DEPENDS ON: ALL modules

## Work Breakdown (7 Steps)

### Step 1: Foundation (4 parallel agents)
**No dependencies - work simultaneously**

**step1a/core-add-types** → `src/types.zig`
- All data structures
- TreeEntry, Stats, Config, ErrorType enums
- Performance metrics structs
- JSON output structs

**step1b/core-add-config** → `src/config.zig`
- Token limit resolution (env var > param > default)
- Limit clamping (1k-100k)
- Large directory path constants

**step1c/core-add-errors** → `src/errors.zig`
- Error type definitions
- Fatal vs non-fatal categorization
- Error message formatting
- MCP error response builders

**step1d/core-add-performance** → `src/performance.zig`
- Performance tracking struct
- Timer utilities (high-resolution)
- Memory tracking setup
- Metric calculation functions

### Step 2: Independent Subsystems (3 parallel agents)
**DEPENDS ON: Step 1 (types, errors)**

**step2a/features-add-filter** → `src/filter.zig`
- Extension filtering (include/exclude)
- Pattern matching
- Hidden file logic
- Filter statistics

**step2b/features-add-symlink** → `src/symlink.zig`
- Symlink detection
- Cycle detection (inode-based)
- Symlink tracking
- Target resolution

**step2c/features-add-safeguards** → `src/safeguards.zig`
- Large directory detection
- UTF-8 filename validation
- Force flag handling
- Fatal error responses

### Step 3: Core Traversal (1 agent)
**DEPENDS ON: Step 1 (types, errors) + Step 2 (filter, symlink, safeguards)**

**step3/core-add-traversal** → `src/tree.zig`
- Recursive directory walking
- Depth tracking
- Integration of filters
- Integration of symlink handling
- Integration of safeguards
- UTF-8 validation during traversal
- Entry collection

### Step 4: Output & Main (2 parallel agents)
**DEPENDS ON: Step 1 (types, performance), Step 3 (tree)**

**step4a/core-add-output** → `src/output.zig`
- JSON serialization
- Token counting (4 chars/token)
- UUID filename generation
- File writing with streaming
- Conditional field inclusion (symlinks_detected, errors, performance, _note)

**step4b/core-add-main** → `src/main.zig`
- MCP stdio handler
- Parameter parsing
- Algorithm orchestration (steps 1-11 from PLAN.md)
- Error handling and responses

### Step 5: Build System & Project Setup (1 agent)
**Can run in parallel with Steps 1-4**

**step5/infra-add-build** → `build.zig`, `.gitignore`, `README.md`
- Zig build configuration
- Optimization settings
- Test runner setup
- Project documentation

### Step 6: Test Infrastructure (2 parallel agents)
**DEPENDS ON: Steps 1-4 complete**

**step6a/tests-add-unit** → `test/unit/*.zig`
- Unit tests for all modules
- Filter logic tests
- Config resolution tests
- Error formatting tests
- Performance metrics tests
- Symlink detection tests
- UTF-8 validation tests

**step6b/tests-add-integration** → `test/integration/*.zig`
- End-to-end traversal tests
- MCP stdio protocol tests
- Token limit enforcement tests
- File mode tests
- Large directory tests

### Step 7: Test Fixtures (1 agent)
**Can run in parallel with Step 6**

**step7/tests-add-fixtures** → `test/fixtures/*`
- Create fixture directories:
  - basic/ - simple structure
  - deep/ - 10+ levels
  - wide/ - many files
  - mixed/ - various types
  - symlinks/ - file and dir symlinks
  - symlink-cycle/ - circular symlinks
  - utf8/ - UTF-8 edge cases
  - non-utf8/ - invalid UTF-8
  - large/ - exceeds 10k tokens

## Worktree Setup

### Base Preparation
```bash
cd ~/Documents/Code/Go_dev/terse-mcp/stump
git checkout main
git pull

# Record base commit
BASE_COMMIT=$(git rev-parse HEAD)
echo "Base commit: $BASE_COMMIT"
```

### Create All Worktrees
```bash
# Step 1 (4 worktrees)
git worktree add -b step1a/core-add-types ../stump-step1a-core-add-types
git worktree add -b step1b/core-add-config ../stump-step1b-core-add-config
git worktree add -b step1c/core-add-errors ../stump-step1c-core-add-errors
git worktree add -b step1d/core-add-performance ../stump-step1d-core-add-performance

# Step 2 (3 worktrees)
git worktree add -b step2a/features-add-filter ../stump-step2a-features-add-filter
git worktree add -b step2b/features-add-symlink ../stump-step2b-features-add-symlink
git worktree add -b step2c/features-add-safeguards ../stump-step2c-features-add-safeguards

# Step 3 (1 worktree)
git worktree add -b step3/core-add-traversal ../stump-step3-core-add-traversal

# Step 4 (2 worktrees)
git worktree add -b step4a/core-add-output ../stump-step4a-core-add-output
git worktree add -b step4b/core-add-main ../stump-step4b-core-add-main

# Step 5 (1 worktree)
git worktree add -b step5/infra-add-build ../stump-step5-infra-add-build

# Step 6 (2 worktrees)
git worktree add -b step6a/tests-add-unit ../stump-step6a-tests-add-unit
git worktree add -b step6b/tests-add-integration ../stump-step6b-tests-add-integration

# Step 7 (1 worktree)
git worktree add -b step7/tests-add-fixtures ../stump-step7-tests-add-fixtures
```

### Verify Worktrees
```bash
git worktree list
# Should show 15 worktrees total
```

## MCP Project Setup

### Prerequisites

Ensure the concurrent-agent MCP server is running:
```bash
# Check if MCP server is available
# The server should be configured in your Claude Code MCP settings
```

### Create Project with Coordinator Agent

The coordinator agent should use MCP tools to set up the project:

**Step 1: Create the project**
```
Use mcp__concurrent-agent-mcp__create_project with:
- name: "stump"
- base_commit: <git rev-parse HEAD>
- steps: JSON array of step definitions (see below)
```

**Step definitions format:**
```json
[
  {"step_num": 1, "branch": "step1a/core-add-types", "scope": "core", "depends_on": []},
  {"step_num": 2, "branch": "step1b/core-add-config", "scope": "core", "depends_on": []},
  {"step_num": 3, "branch": "step1c/core-add-errors", "scope": "core", "depends_on": []},
  {"step_num": 4, "branch": "step1d/core-add-performance", "scope": "core", "depends_on": []},
  {"step_num": 5, "branch": "step2a/features-add-filter", "scope": "features", "depends_on": [1, 3]},
  {"step_num": 6, "branch": "step2b/features-add-symlink", "scope": "features", "depends_on": [1, 3]},
  {"step_num": 7, "branch": "step2c/features-add-safeguards", "scope": "features", "depends_on": [1, 3]},
  {"step_num": 8, "branch": "step3/core-add-traversal", "scope": "core", "depends_on": [1, 3, 5, 6, 7]},
  {"step_num": 9, "branch": "step4a/core-add-output", "scope": "core", "depends_on": [1, 4]},
  {"step_num": 10, "branch": "step4b/core-add-main", "scope": "core", "depends_on": [1, 2, 3, 4, 8, 9]},
  {"step_num": 11, "branch": "step5/infra-add-build", "scope": "infra", "depends_on": []},
  {"step_num": 12, "branch": "step6a/tests-add-unit", "scope": "tests", "depends_on": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]},
  {"step_num": 13, "branch": "step6b/tests-add-integration", "scope": "tests", "depends_on": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]},
  {"step_num": 14, "branch": "step7/tests-add-fixtures", "scope": "tests", "depends_on": []}
]
```

**Step metadata (stored in documentation):**

| Step | Branch | Files | Notes |
|------|--------|-------|-------|
| 1 | step1a/core-add-types | src/types.zig | Core data structures - no dependencies |
| 2 | step1b/core-add-config | src/config.zig | Configuration resolution - no dependencies |
| 3 | step1c/core-add-errors | src/errors.zig | Error types and formatting - no dependencies |
| 4 | step1d/core-add-performance | src/performance.zig | Performance tracking - needs types.zig interface only |
| 5 | step2a/features-add-filter | src/filter.zig | Filtering logic - needs types and errors |
| 6 | step2b/features-add-symlink | src/symlink.zig | Symlink handling - needs types and errors |
| 7 | step2c/features-add-safeguards | src/safeguards.zig | Safety checks - needs types and errors |
| 8 | step3/core-add-traversal | src/tree.zig | Core traversal - integrates all step 2 modules |
| 9 | step4a/core-add-output | src/output.zig | JSON output and serialization |
| 10 | step4b/core-add-main | src/main.zig | MCP stdio handler - orchestrates everything |
| 11 | step5/infra-add-build | build.zig, .gitignore, README.md | Build system - can work independently |
| 12 | step6a/tests-add-unit | test/unit/*.zig | Unit tests for all modules |
| 13 | step6b/tests-add-integration | test/integration/*.zig | Integration tests |
| 14 | step7/tests-add-fixtures | test/fixtures/**/* | Test fixture directories - can work independently |


**Step 2: Verify project creation**
```
Use mcp__concurrent-agent-mcp__get_project with name: "stump" to verify
```

## Agent Assignment & Execution

### Wave 1: Foundation (Parallel - 5 agents)
**Start immediately:**

- **Agent 1** → step1a/core-add-types
- **Agent 2** → step1b/core-add-config
- **Agent 3** → step1c/core-add-errors
- **Agent 4** → step1d/core-add-performance
- **Agent 5** → step5/infra-add-build (independent)

**Each agent:**
1. Use `claim_step` MCP tool to atomically claim next available step
2. Use `start_step` MCP tool to mark as in progress
3. Implement module with periodic `heartbeat` MCP tool calls
4. Commit and push
5. Use `complete_step` MCP tool with commit hash

### Wave 2: Subsystems (Parallel - 3 agents)
**Wait for: step1a, step1c complete**

- **Agent 1** → step2a/features-add-filter
- **Agent 2** → step2b/features-add-symlink
- **Agent 3** → step2c/features-add-safeguards

### Wave 3: Core Traversal (1 agent)
**Wait for: step1a, step1c, step2a, step2b, step2c complete**

- **Agent 1** → step3/core-add-traversal

### Wave 4: Output & Main (Parallel - 2 agents)
**step4a wait for: step1a, step1d**
**step4b wait for: ALL previous steps**

- **Agent 1** → step4a/core-add-output (can start after Wave 1)
- **Agent 2** → step4b/core-add-main (must wait for step3, step4a)

### Wave 5: Tests (Parallel - 3 agents)
**Wait for: ALL code steps complete (step1-4)**

- **Agent 1** → step6a/tests-add-unit
- **Agent 2** → step6b/tests-add-integration
- **Agent 3** → step7/tests-add-fixtures (can start anytime)

## Merge Order

**Critical: Merge in exact step order**

```bash
cd ~/Documents/Code/Go_dev/terse-mcp/stump
git checkout main

# Step 1 - Foundation (any order within step)
git merge step1a/core-add-types
git merge step1b/core-add-config
git merge step1c/core-add-errors
git merge step1d/core-add-performance

# Step 2 - Subsystems (any order within step)
git merge step2a/features-add-filter
git merge step2b/features-add-symlink
git merge step2c/features-add-safeguards

# Step 3 - Core traversal
git merge step3/core-add-traversal

# Step 4 - Output and main (4a before 4b)
git merge step4a/core-add-output
git merge step4b/core-add-main

# Step 5 - Build (anytime, but logical here)
git merge step5/infra-add-build

# Step 6 & 7 - Tests (any order)
git merge step6a/tests-add-unit
git merge step6b/tests-add-integration
git merge step7/tests-add-fixtures

# Push to remote
git push origin main
```

## Conflict Prevention

### File Ownership Matrix

| File | Owner Step | Safe Parallel With |
|------|-----------|-------------------|
| src/types.zig | step1a | All others |
| src/config.zig | step1b | All others |
| src/errors.zig | step1c | All others |
| src/performance.zig | step1d | All others |
| src/filter.zig | step2a | step2b, step2c |
| src/symlink.zig | step2b | step2a, step2c |
| src/safeguards.zig | step2c | step2a, step2b |
| src/tree.zig | step3 | All before step3 |
| src/output.zig | step4a | All except step4b |
| src/main.zig | step4b | None (integrates all) |
| build.zig | step5 | All |
| test/* | step6a, step6b, step7 | Each other |

### Rules
1. **Never modify same file in different steps**
2. **Step numbers enforce merge order**
3. **Dependencies documented in tracking file**
4. **Review tracking file before starting work**

## Status Checking with MCP Tools

### Check Overall Progress
```
Use mcp__concurrent-agent-mcp__get_project with:
- name: "stump"

Returns project details and all steps with their current status
```

### Find Available Work
```
Use mcp__concurrent-agent-mcp__get_available_steps with:
- project: "stump"

Returns all steps ready to work on (dependencies satisfied, not claimed)
```

### Check Project Metrics
```
Use mcp__concurrent-agent-mcp__get_metrics with:
- project: "stump"

Returns completion stats, agent activity, timing information
```

## Agent Workflow Template

### Before Starting
```
1. Use mcp__concurrent-agent-mcp__get_available_steps with project: "stump"
   to see steps ready to claim

2. Use mcp__concurrent-agent-mcp__claim_step with:
   - project: "stump"
   - agent_id: "agent-<name>"

   This atomically claims the next available step (prevents race conditions)
   Returns: step_id and step details

3. Use mcp__concurrent-agent-mcp__start_step with:
   - step_id: <from claim response>
   - worktree: "../stump-<branch-name>"

4. Navigate to worktree directory
```

### During Work
```
# Commit frequently
git add .
git commit -m "Implement core data structures"
git push -u origin <branch-name>

# Send heartbeat every 30-60 seconds while working
Use mcp__concurrent-agent-mcp__heartbeat with:
- step_id: <your step id>
- agent_id: "agent-<name>"

This prevents the step from being marked as stale
```

### After Completing
```
# Final commit
git add .
git commit -m "Complete types.zig implementation"
git push

# Mark step as completed
Use mcp__concurrent-agent-mcp__complete_step with:
- step_id: <your step id>
- commit_hash: <git rev-parse HEAD>
- files_modified: JSON array of modified files
- notes: "Completed all data structures"

The system automatically makes dependent steps available
```

## Benefits of MCP Concurrent-Agent Infrastructure

The MCP concurrent-agent server provides several advantages over JSON file tracking:

- **Atomic operations** - `claim_step` prevents race conditions with database-level locking
- **Real-time coordination** - All agents see updates instantly via shared SQLite database
- **Automatic dependency resolution** - System tracks dependencies and makes steps available when ready
- **Heartbeat monitoring** - Detects stale/crashed agents automatically
- **Comprehensive metrics** - Track completion rates, agent productivity, bottlenecks
- **Event history** - Full audit trail of all state changes
- **Stale work recovery** - Can reassign abandoned work to other agents
- **No manual synchronization** - No need for file locking or conflict resolution

### How It Works

1. **SQLite database** stores all project and step state
2. **Atomic transactions** ensure consistency across concurrent agents
3. **Foreign key constraints** enforce dependency relationships
4. **Heartbeat timestamps** track agent liveness
5. **Event log** records all state transitions for debugging

## Cleanup After Merge

```bash
cd ~/Documents/Code/Go_dev/terse-mcp/stump

# Remove all worktrees
git worktree remove ../stump-step1a-core-add-types
git worktree remove ../stump-step1b-core-add-config
git worktree remove ../stump-step1c-core-add-errors
git worktree remove ../stump-step1d-core-add-performance
git worktree remove ../stump-step2a-features-add-filter
git worktree remove ../stump-step2b-features-add-symlink
git worktree remove ../stump-step2c-features-add-safeguards
git worktree remove ../stump-step3-core-add-traversal
git worktree remove ../stump-step4a-core-add-output
git worktree remove ../stump-step4b-core-add-main
git worktree remove ../stump-step5-infra-add-build
git worktree remove ../stump-step6a-tests-add-unit
git worktree remove ../stump-step6b-tests-add-integration
git worktree remove ../stump-step7-tests-add-fixtures

# Delete branches
git branch -d step1a/core-add-types step1b/core-add-config step1c/core-add-errors step1d/core-add-performance
git branch -d step2a/features-add-filter step2b/features-add-symlink step2c/features-add-safeguards
git branch -d step3/core-add-traversal
git branch -d step4a/core-add-output step4b/core-add-main
git branch -d step5/infra-add-build
git branch -d step6a/tests-add-unit step6b/tests-add-integration step7/tests-add-fixtures

# Clean up worktree metadata
git worktree prune

echo "✓ Cleanup complete"
```

**Note:** The MCP database retains project history for metrics and auditing. The project remains in "completed" status in the database unless explicitly deleted.

## Summary

**Total Steps:** 14 (step1a-d, step2a-c, step3, step4a-b, step5, step6a-b, step7)
**Waves:** 5 waves of parallel work
**Max Parallelism:** 5 agents simultaneously (Wave 1)
**Critical Path:** step1a/c → step2a/b/c → step3 → step4b → merge

**Expected Timeline:**
- Wave 1 (5 parallel): ~2-3 hours
- Wave 2 (3 parallel): ~2-3 hours
- Wave 3 (1 agent): ~3-4 hours
- Wave 4 (2 parallel): ~2-3 hours
- Wave 5 (3 parallel): ~3-4 hours
- **Total:** ~12-17 hours of agent work, ~4-6 hours wall time with parallelism

**Keys to Success:**
1. ✓ All agents check dependencies before starting
2. ✓ Update tracking file frequently
3. ✓ Commit and push often
4. ✓ Merge in exact step order
5. ✓ No file overlap between parallel steps
6. ✓ Clean up after successful merge
