# MiniMax Agent Clone — OpenClaw Integration Guide

## Overview

This project uses **OpenClaw** as the AI agent orchestration layer with **GitHub Issues** for task tracking and **gh CLI** for all GitHub operations.

## Project Files

| File | Purpose |
|------|---------|
| `openclaw.json` | Project config (GitHub repo, phases, skills) |
| `macos_agent_tasks.md` | Full task breakdown (315 tasks, 10 phases) |
| `MINIMAX_AGENT_CLONE_SPEC.md` | Product specification |
| `.github/workflows/ci.yml` | GitHub Actions CI |
| `scripts/manage-tasks.sh` | Task management via gh CLI |

## Skills Installed

| Skill | Location | Purpose |
|-------|----------|---------|
| `code-review-fix-loop` | `~/.openclaw/skills/code-review-fix-loop/` | 10-iteration review-fix loop |

## How the Loop Works

```
You message OpenClaw (Discord/Telegram/Slack)
    ↓
"@agent /code-review-loop Phase 2"
    ↓
OpenClaw loads code-review-fix-loop skill
    ↓
Iteration 1: /code-review → find issues → apply_patch fixes
    ↓
Iteration 2: /code-review on new diff → fix remaining
    ↓
... (up to 10 iterations)
    ↓
Clean: git commit → gh pr create
Incomplete: gh issue create for remaining findings
```

## Task Management

Tasks are managed via **GitHub Issues** using `gh` CLI.

### Initialize Tasks (One-time setup)
```bash
cd ~/git/minimax-agent
./scripts/manage-tasks.sh init
```

### Common Commands
```bash
./scripts/manage-tasks.sh status      # Show progress by phase
./scripts/manage-tasks.sh next       # Show next P0 task
./scripts/manage-tasks.sh list 2     # List Phase 2 tasks
./scripts/manage-tasks.sh remaining   # Show remaining P0 tasks
./scripts/manage-tasks.sh report      # Generate markdown report
```

### Manual GitHub Operations
```bash
# Create issue
gh issue create --title "[Phase 2] Chat UI" --body "..." --label "phase-2,P0"

# List issues
gh issue list --label "phase-2" --state open

# Create PR
gh pr create --title "feat: Phase 2 chat UI" --body "## Summary\n..."

# Check PR status
gh pr status
```

## Integration with OpenClaw

OpenClaw's `code-review-fix-loop` skill uses `gh` for:

1. **Before loop**: Check existing issues, current branch
2. **During loop**: After fixes, track progress in issue comments
3. **After loop**:
   - Clean: `git commit` → `gh pr create`
   - Incomplete: `gh issue create` for remaining findings

### GitHub Labels Used

| Label | Purpose |
|-------|---------|
| `phase-1` through `phase-10` | Phase assignment |
| `P0`, `P1`, `P2` | Priority |
| `task` | All tasks |
| `in-progress` | Currently being worked |
| `done` | Completed |
| `code-review` | Code review findings |
| `remaining` | Unfixed after loop |

## Workflow: Implement Phase 1

```bash
# 1. Claim next P0 task
./scripts/manage-tasks.sh next

# 2. Start OpenClaw loop
# Message OpenClaw: "@agent /code-review-loop Phase 1"

# 3. OpenClaw will:
#    - Review code
#    - Apply fixes iteratively
#    - Commit when clean OR create issues for remaining

# 4. Check results
gh pr status
gh issue list --label "phase-1"
```

## Workflow: Code Review PR

```bash
# 1. Create feature branch
git checkout -b "review/phase-2-$(date +%Y%m%d)"

# 2. Run OpenClaw on the diff
# Message OpenClaw: "@agent /code-review-loop --scope=diff"

# 3. After loop completes:
gh pr status  # Check PR state

# 4. Push if needed
git push -u origin HEAD
```

## Configuration

### openclaw.json Keys
```json
{
  "github": {
    "owner": "YOUR_GITHUB_USERNAME",
    "repo": "minimax-agent",
    "default_branch": "main"
  },
  "code_review": {
    "loop_enabled": true,
    "max_iterations": 10,
    "auto_commit": true,
    "auto_pr": true,
    "auto_issue": true
  }
}
```

### Environment Variables
```bash
GITHUB_TOKEN          # gh CLI auth (usually auto from gh auth)
GITHUB_REPO           # Override repo detection (owner/repo format)
```

## Slash Commands in OpenClaw

| Command | Description |
|---------|-------------|
| `/code-review-loop <phase>` | Run 10-iteration review-fix loop |
| `/crl <phase>` | Shorthand for code-review-loop |
| `/minimax-agent status` | Check phase implementation status |
| `/agentic <task>` | Run agentic coding task |

## How the Skill Manages All Tasks

The `code-review-fix-loop` skill is designed to handle any task from `macos_agent_tasks.md`:

1. **Phase scoping**: The skill reads `macos_agent_tasks.md` to understand Phase scope
2. **Task selection**: You specify which phase/tasks to target
3. **10-iteration limit**: Prevents infinite loops while ensuring thorough review
4. **GitHub integration**: Creates issues for remaining work, PRs for completed work
5. **Persistence**: GitHub Issues track state across OpenClaw sessions

### Task → Issue → PR Flow

```
macos_agent_tasks.md
    ↓ (manage-tasks.sh init)
GitHub Issues (one per task)
    ↓
OpenClaw /code-review-loop
    ↓
Iterations 1-10:
    - review → fix → commit/issue
    ↓
Completed: PR merged
Remaining: Issues with labels
    ↓
Next phase: repeat
```

## CI/CD

GitHub Actions (`.github/workflows/ci.yml`) runs on:
- Push to main
- Pull requests
- Manual trigger

Jobs:
- Lint & format check
- Build check (macOS)
- Code review loop (on PRs)

## Tips

1. **Run `init` once** after cloning the repo to create all issues
2. **Use `next`** to always know what to work on next
3. **Check `status`** to see overall progress
4. **Issues auto-labeled** by phase and priority
5. **PRs auto-linked** to source issues

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `gh: command not found` | Install GitHub CLI: `brew install gh` |
| `gh auth login` needed | Run `gh auth login` |
| Wrong repo detected | Set `GITHUB_REPO=owner/repo` env var |
| OpenClaw skill not found | Check `~/.openclaw/skills/code-review-fix-loop/` exists |
| Loop not stopping | Check `max_iterations` in skill config |
