# Agent Quick Start Guide

Quick reference for Claude agents working on stump concurrent development.

## Before You Start

**Read first:**
1. `PLAN.md` - Main project specification
2. `CONCURRENT-PLAN.md` - Detailed concurrent development plan
3. This file - Quick start checklist

## Step 1: Check What's Available

```
Use MCP tool: mcp__concurrent-agent-mcp__get_available_steps
- project: "stump"

Returns all steps with satisfied dependencies that are not yet claimed
```

## Step 2: Check Dependencies (If Needed)

```
Use MCP tool: mcp__concurrent-agent-mcp__get_step
- step_id: <step number>

Returns step details including dependency status

OR simply use get_available_steps which only returns steps with satisfied dependencies
```

## Step 3: Claim Your Step

```
Use MCP tool: mcp__concurrent-agent-mcp__claim_step
- project: "stump"
- agent_id: "agent-<your-name>"

This atomically claims the next available step (prevents race conditions)
Returns the step_id and branch name
```

## Step 4: Start Work and Navigate to Worktree

```
Use MCP tool: mcp__concurrent-agent-mcp__start_step
- step_id: <from claim response>
- worktree: "../stump-<branch-name>"

Then navigate to the worktree:
cd ../stump-<branch-name>
```

## Step 5: Implement Your Module

**Read the spec from CONCURRENT-PLAN.md for your step**

### Example: step1a/core-add-types

**File:** `src/types.zig`

**What to implement:**
- TreeEntry struct
- Stats struct
- Config struct
- ErrorType enum
- Performance metrics structs
- JSON output structs

**Reference:** See PLAN.md "Output Format Design" and other sections

### Commit Often

```bash
git add .
git commit -m "Add TreeEntry and Stats structs"
git push -u origin <branch-name>

# Send periodic heartbeats while working (every 30-60 seconds)
Use MCP tool: mcp__concurrent-agent-mcp__heartbeat
- step_id: <your step id>
- agent_id: "agent-<your-name>"

This prevents your step from being marked as stale
```

## Step 6: Mark Complete

```bash
# Final commit
git add .
git commit -m "Complete types.zig implementation"
git push

# Mark as completed
Use MCP tool: mcp__concurrent-agent-mcp__complete_step
- step_id: <your step id>
- commit_hash: <git rev-parse HEAD output>
- files_modified: ["src/types.zig"]
- notes: "Completed all data structures and type definitions"

The system automatically makes dependent steps available for other agents
```

## Step 7: Verify Status

```
Use MCP tool: mcp__concurrent-agent-mcp__get_project
- name: "stump"

Check that your step shows as completed and view overall project progress
Dependent steps are automatically made available by the system
```

## Quick Commands Cheat Sheet

```
# See overall project status
mcp__concurrent-agent-mcp__get_project
- name: "stump"

# See available steps
mcp__concurrent-agent-mcp__get_available_steps
- project: "stump"

# Claim next available step
mcp__concurrent-agent-mcp__claim_step
- project: "stump"
- agent_id: "agent-<name>"

# Start working on claimed step
mcp__concurrent-agent-mcp__start_step
- step_id: <from claim>
- worktree: "../stump-<branch>"

# Send heartbeat (every 30-60 sec while working)
mcp__concurrent-agent-mcp__heartbeat
- step_id: <your step>
- agent_id: "agent-<name>"

# Mark step complete
mcp__concurrent-agent-mcp__complete_step
- step_id: <your step>
- commit_hash: <git rev-parse HEAD>
- files_modified: ["src/file.zig"]
- notes: "Completion notes"

# View metrics
mcp__concurrent-agent-mcp__get_metrics
- project: "stump"
```

## Common Scenarios

### Scenario 1: I'm Agent 1, Starting Fresh

```
# 1. Check what's available
Use mcp__concurrent-agent-mcp__get_available_steps with project: "stump"

# 2. Claim a step
Use mcp__concurrent-agent-mcp__claim_step with:
- project: "stump"
- agent_id: "agent-1"

# 3. Start the step
Use mcp__concurrent-agent-mcp__start_step with:
- step_id: <from claim>
- worktree: "../stump-<branch-name>"

# 4. Go to worktree
cd ../stump-<branch-name>

# 5. Implement (see CONCURRENT-PLAN.md for details)
... code ...
... send periodic heartbeats ...

# 6. Commit and complete
git add . && git commit -m "Complete types.zig" && git push

Use mcp__concurrent-agent-mcp__complete_step with:
- step_id: <your step>
- commit_hash: <git rev-parse HEAD>
- files_modified: ["src/types.zig"]
```

### Scenario 2: Dependencies Not Yet Satisfied

```
# 1. Check if your desired step is available
Use mcp__concurrent-agent-mcp__get_available_steps with project: "stump"

# If the step you want isn't listed:
# → Its dependencies are not yet complete
# → Wait or work on a different available step

# 2. Check overall status to see what's blocking
Use mcp__concurrent-agent-mcp__get_project with name: "stump"

# 3. When dependencies complete, the step becomes available automatically
# Claim it as soon as it appears in get_available_steps
```

### Scenario 3: Checking Overall Progress

```
Use mcp__concurrent-agent-mcp__get_project with name: "stump"

Returns all steps with:
- status (not_started, claimed, in_progress, completed)
- assigned agent
- dependencies
- timestamps

Use mcp__concurrent-agent-mcp__get_metrics with project: "stump"

Returns:
- Completion percentage
- Active agents
- Average step duration
- Bottlenecks
```

## Module Implementation Guidelines

### Read the interfaces you depend on

If your step depends on another (e.g., step2a depends on step1a):

```bash
# Read the completed dependency
cd ~/Documents/Code/Go_dev/terse-mcp/stump
git show step1a/core-add-types:src/types.zig

# Or checkout to review
cd ../stump-step1a-core-add-types
cat src/types.zig
cd ../stump-step2a-features-add-filter
```

### Follow Zig best practices

- Early returns
- No OOP
- Minimal abstraction
- Clear error handling

### Reference PLAN.md constantly

Each module has clear specifications in PLAN.md:
- types.zig → "Output Format Design", "Core Features"
- config.zig → "Token Counting" section
- errors.zig → "Warning System and Force Flag"
- etc.

### Write tests as you go

Even though formal tests are step6-7, add basic tests to verify your module works.

## Troubleshooting

### "No steps available"

All available steps are claimed or dependencies not satisfied.

```
Check current state:
Use mcp__concurrent-agent-mcp__get_project with name: "stump"

This shows which steps are blocked and why
```

### "Step already claimed"

`claim_step` failed because another agent claimed it first. The MCP system uses atomic operations to prevent this, but it can happen if multiple agents claim simultaneously.

```
Simply call claim_step again to get the next available step
```

### "Heartbeat timeout"

If you stop sending heartbeats for too long, your step may be marked as stale.

```
Use mcp__concurrent-agent-mcp__detect_stale_work to check
Use mcp__concurrent-agent-mcp__recover_step to reclaim if needed
```

### "Project not found"

The coordinator hasn't set up the project yet.

```
Coordinator needs to use mcp__concurrent-agent-mcp__create_project
See CONCURRENT-PLAN.md for project setup instructions
```

### "Worktree doesn't exist"

```bash
# Check if worktrees were created
git worktree list

# If missing, coordinator needs to run worktree setup
cd ~/Documents/Code/Go_dev/terse-mcp/stump
# Follow worktree creation steps from CONCURRENT-PLAN.md
```

## Critical Rules

1. **Never modify files owned by other steps**
2. **Use claim_step to atomically claim work** (prevents conflicts)
3. **Send heartbeats every 30-60 seconds while working** (prevents stale detection)
4. **Commit and push frequently**
5. **Use complete_step when done** (makes dependent steps available)
6. **Don't merge - coordinator will merge in order**

## File Ownership (Don't Cross!)

| Your Step | Your Files | Don't Touch |
|-----------|-----------|-------------|
| step1a | src/types.zig | Everything else |
| step1b | src/config.zig | Everything else |
| step1c | src/errors.zig | Everything else |
| step1d | src/performance.zig | Everything else |
| step2a | src/filter.zig | Everything else |
| step2b | src/symlink.zig | Everything else |
| step2c | src/safeguards.zig | Everything else |
| step3 | src/tree.zig | Everything else |
| step4a | src/output.zig | Everything else |
| step4b | src/main.zig | Everything else |
| step5 | build.zig, .gitignore, README.md | src/* |
| step6a | test/unit/*.zig | src/*, test/integration/* |
| step6b | test/integration/*.zig | src/*, test/unit/* |
| step7 | test/fixtures/**/* | src/*, test/*.zig |

## Questions?

1. Check `CONCURRENT-PLAN.md` - detailed workflow
2. Check `PLAN.md` - module specifications
3. Use `get_project` MCP tool to check current status
4. Use `get_metrics` MCP tool to see overall progress
5. Coordinate with other agents via MCP project state

## Summary Workflow

```
1. get_available_steps → 2. claim_step → 3. start_step →
4. Navigate to worktree → 5. Implement with heartbeats →
6. Commit often → 7. complete_step → 8. Verify with get_project
```

**Remember:** You're part of a team. Send heartbeats while working. Respect file ownership. The MCP system handles dependency coordination automatically.
