#!/bin/bash
# 🌊 MiniMax Agent — Parallel Worktree Pool Manager
# Runs N parallel worktrees, each implementing a P0 issue independently.
# After PR merge → deletes worktree + branch, picks up next issue.
#
# Usage: ./scripts/worktree-pool.sh [start|stop|status|cleanup]
# Environment: GH_TOKEN must be available (export GH_TOKEN=$(gh auth token))

set -e

REPO_DIR="$HOME/git/minimax-agent"
GITHUB_REPO="lucid-fabrics/minimax-agent"
POOL_SIZE="${POOL_SIZE:-3}"
WORKTREE_BASE="$HOME/git"
STATE_FILE="$HOME/.openclaw/jobs/mm-pool-state.json"
LOG_FILE="$HOME/.openclaw/logs/mm-pool.log"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log() { echo -e "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# ─── Helpers ─────────────────────────────────────────────────────────────────

get_token() {
  export GH_TOKEN
  if [ -z "$GH_TOKEN" ]; then
    GH_TOKEN=$(gh auth token 2>/dev/null) || { log "${RED}❌ gh auth required${NC}"; exit 1; }
  fi
}

get_github_token() { gh auth token 2>/dev/null; }

is_worktree_active() {
  local issue_num=$1
  local wt_dir="$WORKTREE_BASE/mm-issue-$issue_num"
  # Check if worktree dir exists and branch was recently modified (within 10 min)
  if [ -d "$wt_dir" ]; then
    local last_mod=$(stat -f%m "$wt_dir" 2>/dev/null || stat -c%Y "$wt_dir" 2>/dev/null)
    local now=$(date +%s)
    local age=$((now - last_mod))
    [ "$age" -lt 600 ]  # active if modified in last 10 min
  else
    return 1
  fi
}

get_idle_worktrees() {
  # Worktrees that exist but are not actively running a build
  for wt_dir in "$WORKTREE_BASE"/mm-issue-*; do
    [ -d "$wt_dir" ] || continue
    local wt_name=$(basename "$wt_dir")
    local issue_num=${wt_name#mm-issue-}

    # Check if worktree is still running (pid file exists and process alive)
    if [ -f "$wt_dir/.worktree.pid" ]; then
      local pid=$(cat "$wt_dir/.worktree.pid")
      if kill -0 "$pid" 2>/dev/null; then
        continue  # busy
      fi
    fi

    # Worktree exists but not running → could mean done or abandoned
    # Check if branch was merged
    local branch_name=$(git -C "$wt_dir" branch --show-current 2>/dev/null || echo "")
    if [ -n "$branch_name" ]; then
      local merged=$(git -C "$REPO_DIR" branch -r --merged origin/main 2>/dev/null | grep "$branch_name" | wc -l)
      if [ "$merged" -gt 0 ]; then
        log "${YELLOW}🧹 Cleaning up merged worktree: $wt_name${NC}"
        git -C "$REPO_DIR" worktree remove "$wt_dir" --force 2>/dev/null || true
        git -C "$REPO_DIR" push origin --delete "$branch_name" 2>/dev/null || true
        continue
      fi
    fi

    # Not merged, not running → might be mid-build, check age
    local last_mod=$(stat -f%m "$wt_dir" 2>/dev/null || stat -c%Y "$wt_dir" 2>/dev/null)
    local now=$(date +%s)
    local age=$((now - last_mod))
    if [ "$age" -gt 300 ]; then
      # Abandoned worktree (>5 min no activity), clean it up
      log "${YELLOW}🧹 Removing abandoned worktree: $wt_name${NC}"
      git -C "$REPO_DIR" worktree remove "$wt_dir" --force 2>/dev/null || true
    fi
  done
}

get_active_worktree_count() {
  local count=0
  for wt_dir in "$WORKTREE_BASE"/mm-issue-*; do
    [ -d "$wt_dir" ] || continue
    if [ -f "$wt_dir/.worktree.pid" ]; then
      local pid=$(cat "$wt_dir/.worktree.pid")
      if kill -0 "$pid" 2>/dev/null; then
        ((count++))
      fi
    fi
  done
  echo "$count"
}

get_next_unclaimed_issue() {
  # Find first open P0 issue without the in-progress label name
  # (jq contains() on arrays doesn't work on objects, use any(.name=="x") instead)
  local raw=$(gh issue list \
    --repo "$GITHUB_REPO" \
    --label "P0" \
    --state open \
    --json number,title,labels \
    --jq '[.[] | select([.labels[] | .name] | contains(["in-progress"]) | not)] | .[0]' 2>/dev/null)

  if [ -z "$raw" ] || [ "$raw" = "null" ]; then
    echo ""
    return
  fi

  local issue_num=$(echo "$raw" | jq -r '.number')
  # Skip if worktree already exists
  if [ -d "$WORKTREE_BASE/mm-issue-$issue_num" ]; then
    echo ""
    return
  fi

  echo "$raw"
}

claim_issue() {
  local issue_num=$1
  gh issue edit "$issue_num" --repo "$GITHUB_REPO" --add-label "in-progress" 2>/dev/null
}

slugify() {
  echo "$1" | sed 's/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]' | cut -c1-50
}

# ─── Launch a single issue in a worktree ──────────────────────────────────────

launch_issue() {
  local issue_num=$1
  local issue_title=$2

  local wt_name="mm-issue-$issue_num"
  local wt_dir="$WORKTREE_BASE/$wt_name"
  local branch_name="fix/$issue_num-$(slugify "$issue_title")"

  # Skip if worktree dir already exists (stale from previous run)
  if [ -d "$wt_dir" ]; then
    log "${YELLOW}⏭️  Worktree $wt_name already exists, skipping #$issue_num${NC}"
    return 0
  fi

  log "${BLUE}🚀 Launching issue #$issue_num: $issue_title${NC}"

  # Create worktree + branch FIRST
  cd "$REPO_DIR"
  git fetch origin main --quiet 2>/dev/null

  if ! git worktree add "$wt_dir" "origin/main" -b "$branch_name" 2>/dev/null; then
    log "${RED}❌ Failed to create worktree for #$issue_num${NC}"
    return 1
  fi

  # Claim the issue (after worktree exists to avoid race)
  if ! claim_issue "$issue_num"; then
    # Rollback worktree on claim failure
    log "${RED}❌ Claim failed for #$issue_num, rolling back${NC}"
    git -C "$REPO_DIR" worktree remove "$wt_dir" --force 2>/dev/null || true
    return 1
  fi

  # Launch Claude Code in the worktree (background)
  (
    export GH_TOKEN=$(get_github_token)
    cd "$wt_dir"

    # Write PID for tracking
    echo $$ > "$wt_dir/.worktree.pid"

    log "${GREEN}⚡ Claude Code building #$issue_num in $wt_dir${NC}"

    # Run Claude Code with the issue task
    claude --print --permission-mode bypassPermissions \
      "You are implementing GitHub issue #$issue_num: \"$issue_title\" for the MiniMax Agent macOS app.

The repo is at: $wt_dir
The main Xcode project is at: $wt_dir/MiniMaxAgent.xcodeproj

## Your task:
1. Read the issue details: gh issue view $issue_num --repo $GITHUB_REPO
2. Read macOS conventions: ~/git/code-conventions-swift/README.md
3. Read project CLAUDE.md: $wt_dir/CLAUDE.md (if exists)
4. Implement the feature/fix completely
5. Build: xcodebuild -project MiniMaxAgent.xcodeproj -scheme MiniMaxAgent -configuration Debug build 2>&1 | tail -5
6. If build fails, fix and retry (max 3 attempts)
7. Create PR: gh pr create --repo $GITHUB_REPO --title \"feat: [#$issue_num] $issue_title\" --body \"Fixes #$issue_num\" --label \"task\"
8. Auto-merge PR: gh pr merge --squash --delete-branch --auto $issue_num --repo $GITHUB_REPO 2>/dev/null || gh pr merge --squash --delete-branch $issue_num --repo $GITHUB_REPO
9. On PR merged: echo \"MERGED\" > \"$wt_dir/.worktree.done\"
10. On any error: echo \"ERROR: \$message\" > \"$wt_dir/.worktree.error\"

Work silently. Report only on completion or irrecoverable error." \
      > "$wt_dir/.worktree.log" 2>&1

    # Remove PID (process finished)
    rm -f "$wt_dir/.worktree.pid"

    local exit_status=$?
    if [ $exit_status -ne 0 ]; then
      log "${RED}❌ Claude Code exited with code $exit_status for #$issue_num${NC}"
    fi
  ) &

  local bg_pid=$!
  echo "$bg_pid" > "$wt_dir/.worktree.pid"
  log "${GREEN}✅ Worktree #$issue_num running as PID $bg_pid${NC}"
}

# ─── Main pool manager ─────────────────────────────────────────────────────────

pool_status() {
  local active=$(get_active_worktree_count)
  local total=0
  echo -e "${BLUE}🌊 Worktree Pool Status${NC}"
  echo "  Pool size: $POOL_SIZE"
  echo "  Active: $active"
  echo ""
  for wt_dir in "$WORKTREE_BASE"/mm-issue-*; do
    [ -d "$wt_dir" ] || continue
    total=$((total+1))
    local wt_name=$(basename "$wt_dir")
    local issue_num=${wt_name#mm-issue-}
    local pid_file="$wt_dir/.worktree.pid"
    local status="${RED}❓ unknown${NC}"
    if [ -f "$pid_file" ]; then
      local pid=$(cat "$pid_file")
      if kill -0 "$pid" 2>/dev/null; then
        status="${GREEN}⚡ running (PID $pid)${NC}"
      else
        if [ -f "$wt_dir/.worktree.done" ]; then
          status="${GREEN}✅ done${NC}"
        elif [ -f "$wt_dir/.worktree.error" ]; then
          status="${RED}❌ error${NC}"
        else
          status="${YELLOW}⚠️  stopped${NC}"
        fi
      fi
    else
      status="${YELLOW}○ idle${NC}"
    fi
    echo "  $wt_name: $status"
  done
  [ "$total" -eq 0 ] && echo "  (no worktrees)"
  echo ""
  echo "  Log: $LOG_FILE"
}

pool_cleanup() {
  log "${YELLOW}🧹 Full cleanup of all worktrees${NC}"
  cd "$REPO_DIR"
  for wt_dir in "$WORKTREE_BASE"/mm-issue-*; do
    [ -d "$wt_dir" ] || continue
    local wt_name=$(basename "$wt_dir")
    local branch=$(git -C "$wt_dir" branch --show-current 2>/dev/null || echo "")
    git -C "$REPO_DIR" worktree remove "$wt_dir" --force 2>/dev/null || true
    if [ -n "$branch" ]; then
      git -C "$REPO_DIR" push origin --delete "$branch" 2>/dev/null || true
    fi
    log "  Removed $wt_name"
  done
  log "${GREEN}✅ Cleanup complete${NC}"
}

pool_tick() {
  # One iteration of pool management
  get_token

  local active=$(get_active_worktree_count)
  local available=$((POOL_SIZE - active))

  log "─── Pool tick: $active active, $available slots ───"

  if [ "$available" -le 0 ]; then
    log "Pool full, nothing to launch."
    return
  fi

  # Launch up to $available new issues
  for i in $(seq 1 "$available"); do
    local issue_json=$(get_next_unclaimed_issue)
    if [ -z "$issue_json" ] || [ "$issue_json" = "null" ]; then
      log "No more unclaimed P0 issues."
      return
    fi

    local issue_num=$(echo "$issue_json" | jq -r '.number')
    local issue_title=$(echo "$issue_json" | jq -r '.title')

    if [ -z "$issue_num" ] || [ "$issue_num" = "null" ]; then
      log "Could not parse issue JSON"
      return
    fi

    launch_issue "$issue_num" "$issue_title"
    sleep 2  # small delay between launches
  done
}

# ─── Entry point ───────────────────────────────────────────────────────────────

COMMAND="${1:-tick}"

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$STATE_FILE")"

case "$COMMAND" in
  start)   pool_tick ;;
  status)  pool_status ;;
  cleanup) pool_cleanup ;;
  tick)    pool_tick ;;
  *)       echo "Usage: $0 [start|status|cleanup]" ;;
esac
