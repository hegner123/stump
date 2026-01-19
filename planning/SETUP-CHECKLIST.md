# Stump Concurrent Development Setup Checklist

Complete these steps before starting multi-agent development.

## Pre-Setup Verification

- [ ] Confirm you're in the main stump repository
- [ ] Confirm main branch is clean and up to date (`git status`)
- [ ] Confirm MCP concurrent-agent server is installed and running
- [ ] Test MCP tools are accessible (try `mcp__concurrent-agent-mcp__list_projects`)
- [ ] Read PLAN.md fully
- [ ] Read CONCURRENT-PLAN.md fully
- [ ] Read AGENT-QUICKSTART.md

## Phase 1: Repository Setup

- [ ] Ensure on main branch: `git checkout main && git pull`
- [ ] Record base commit: `git rev-parse HEAD`
- [ ] Verify working directory is clean

## Phase 2: Worktree Creation

**Manual creation (see CONCURRENT-PLAN.md for full commands):**
- [ ] Create step1a-d worktrees (4 total)
- [ ] Create step2a-c worktrees (3 total)
- [ ] Create step3 worktree (1 total)
- [ ] Create step4a-b worktrees (2 total)
- [ ] Create step5 worktree (1 total)
- [ ] Create step6a-b worktrees (2 total)
- [ ] Create step7 worktree (1 total)
- [ ] Verify: `git worktree list | wc -l` → should show 15 (including main)

## Phase 3: MCP Project Creation

- [ ] Use MCP tool: `mcp__concurrent-agent-mcp__create_project`
  - name: "stump"
  - base_commit: `<output from git rev-parse HEAD>`
  - steps: JSON array of 14 step definitions (see CONCURRENT-PLAN.md)
- [ ] Verify project created: `mcp__concurrent-agent-mcp__get_project` with name: "stump"
- [ ] Confirm all 14 steps are registered
- [ ] Confirm dependencies are correctly set up

## Phase 4: Agent Coordination Setup

**MCP concurrent-agent coordination:**
- [ ] Confirm all agents have access to MCP concurrent-agent server
- [ ] Test that agents can call `mcp__concurrent-agent-mcp__get_project` with name: "stump"
- [ ] Verify agents can see the project and all steps
- [ ] Ensure agents understand heartbeat requirement (every 30-60 sec)

## Phase 5: Agent Briefing

For each agent that will participate:

- [ ] Share AGENT-QUICKSTART.md
- [ ] Confirm agent has MCP concurrent-agent access
- [ ] Confirm agent can call MCP tools successfully
- [ ] Confirm agent understands file ownership rules
- [ ] Confirm agent understands heartbeat requirement
- [ ] Agents will claim steps dynamically (no pre-assignment needed)

**Note:** With MCP, agents dynamically claim available steps. No need for manual assignment.

## Phase 6: Verification Tests

- [ ] Test `mcp__concurrent-agent-mcp__get_available_steps` with project: "stump"
- [ ] Test `mcp__concurrent-agent-mcp__claim_step` with project: "stump", agent_id: "test-agent"
- [ ] Test `mcp__concurrent-agent-mcp__start_step` with returned step_id
- [ ] Test `mcp__concurrent-agent-mcp__heartbeat`
- [ ] Test `mcp__concurrent-agent-mcp__get_project` shows step as in_progress
- [ ] Test worktree navigation works
- [ ] Reset test (mark step as not_started or delete and recreate project)

## Phase 7: Communication Plan

- [ ] Decide how agents communicate (Slack, Discord, shared doc, etc.)
- [ ] Establish notification method for completed steps (optional - MCP tracks automatically)
- [ ] Clarify who will perform final merge
- [ ] Set up monitoring via `mcp__concurrent-agent-mcp__get_metrics` for progress tracking

## Phase 8: Launch Readiness

- [ ] All worktrees created ✓
- [ ] MCP project created ✓
- [ ] MCP tools tested ✓
- [ ] All agents briefed ✓
- [ ] All agents have MCP access ✓
- [ ] Communication established ✓
- [ ] Base commit recorded: `____________`
- [ ] Launch time agreed: `____________`

## Post-Launch Monitoring

During development:

- [ ] Use `mcp__concurrent-agent-mcp__get_project` to monitor status updates
- [ ] Use `mcp__concurrent-agent-mcp__get_metrics` for progress tracking
- [ ] Use `mcp__concurrent-agent-mcp__detect_stale_work` to find crashed agents
- [ ] Watch for blocked steps in project status
- [ ] Monitor agent heartbeats
- [ ] Be ready to help with conflicts or issues

## Final Merge Checklist

When all steps are complete:

- [ ] Verify all steps completed: `mcp__concurrent-agent-mcp__get_project` with name: "stump"
- [ ] All commits pushed to remote
- [ ] Coordinator on main branch
- [ ] Merge branches in order (see CONCURRENT-PLAN.md)
- [ ] Resolve any merge conflicts
- [ ] Run tests
- [ ] Push to remote: `git push origin main`
- [ ] Clean up worktrees (see CONCURRENT-PLAN.md cleanup section)

## Success Criteria

- [ ] 14 steps completed (verify with `mcp__concurrent-agent-mcp__get_project`)
- [ ] All merged to main without conflicts
- [ ] Tests passing
- [ ] Main branch clean
- [ ] Worktrees removed
- [ ] MCP project marked as completed

## Emergency Procedures

**If an agent gets stuck:**
1. Use `mcp__concurrent-agent-mcp__detect_stale_work` to identify stale steps
2. Review the stuck agent's worktree commits
3. Use `mcp__concurrent-agent-mcp__recover_step` to reassign work
4. New agent can continue from where previous agent left off

**If merge conflicts occur:**
1. This shouldn't happen if file ownership was respected
2. Review file ownership matrix in CONCURRENT-PLAN.md
3. Determine which step violated ownership
4. Resolve manually
5. Update documentation if ownership was unclear

**If MCP server becomes unavailable:**
1. Agents should pause work
2. Restart MCP concurrent-agent server
3. Project state is preserved in SQLite database
4. Agents can resume by calling `heartbeat` to reactivate

**If need to restart project:**
1. Complete current in-progress steps if possible
2. Clean up worktrees manually (see CONCURRENT-PLAN.md)
3. Delete project from MCP database or create new project
4. Return to Phase 2
5. Restart with fresh worktrees and new project

## Notes

- Setup time: ~15-30 minutes
- Agent onboarding: ~5-10 minutes per agent
- Total development time: ~4-6 hours wall time (with 5 agents)
- Merge time: ~30 minutes
- Cleanup time: ~5 minutes

## Additional Resources

- **Worktree Documentation**: `~/.claude/WORKTREE*.md` files
- **Project Plan**: `PLAN.md`
- **Concurrent Plan**: `CONCURRENT-PLAN.md`
- **Agent Guide**: `AGENT-QUICKSTART.md`
- **Helper Script**: `scripts/worktree-helper.sh`
