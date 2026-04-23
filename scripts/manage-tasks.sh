#!/bin/bash
# 🌊 MiniMax Agent — Task Management Script
# Manages 315 tasks across 10 phases using GitHub Issues + Labels

# Don't use set -e as gh commands may return non-zero legitimately

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TASKS_FILE="$REPO_DIR/macos_agent_tasks.md"
GITHUB_REPO="${GITHUB_REPO:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
  echo -e "${BLUE}🌊 MiniMax Agent Task Manager${NC}"
  echo ""
  echo "Usage: ./scripts/manage-tasks.sh <command> [options]"
  echo ""
  echo "Commands:"
  echo "  init                    Initialize GitHub issues from macos_agent_tasks.md"
  echo "  list [phase]           List tasks (all or by phase)"
  echo "  status                  Show overall progress"
  echo "  next                    Show next P0 task to work on"
  echo "  claim <task-id>         Claim a task for review"
  echo "  complete <task-id>      Mark task as complete"
  echo "  remaining               Show incomplete P0 tasks"
  echo "  report                  Generate markdown progress report"
  echo ""
  echo "Examples:"
  echo "  ./scripts/manage-tasks.sh init                # Create all GitHub issues"
  echo "  ./scripts/manage-tasks.sh status              # Show progress"
  echo "  ./scripts/manage-tasks.sh next                # Get next task"
  echo "  ./scripts/manage-tasks.sh list Phase 1        # List Phase 1 tasks"
}

# Check gh cli
check_gh() {
  if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ GitHub CLI (gh) is not installed${NC}"
    echo "Install: https://cli.github.com/"
    exit 1
  fi

  if [ -z "$GITHUB_REPO" ]; then
    # Try to detect from git remote
    GITHUB_REPO=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null | sed 's/.*github.com[/:]//' | sed 's/\.git$//' || echo "")
  fi

  if [ -z "$GITHUB_REPO" ]; then
    echo -e "${RED}❌ GITHUB_REPO not set and could not detect from git remote${NC}"
    exit 1
  fi
}

# Initialize GitHub issues from tasks file
cmd_init() {
  check_gh
  echo -e "${YELLOW}📋 Initializing tasks from $TASKS_FILE${NC}"

  if [ ! -f "$TASKS_FILE" ]; then
    echo -e "${RED}❌ Tasks file not found: $TASKS_FILE${NC}"
    exit 1
  fi

  local phase=""
  local task_count=0
  local skipped=0

  # Parse tasks file and create issues
  while IFS= read -r line; do
    # Detect phase headers
    if [[ "$line" =~ ^##\ Phase\ [0-9]+: ]]; then
      phase=$(echo "$line" | sed 's/.*Phase \([0-9]*\):.*/\1/')
      echo -e "${GREEN}Processing Phase $phase${NC}"

    # Detect tasks (checkboxes)
    elif echo "$line" | grep -qE '^  - \[[ x]\] '; then
      local task=$(echo "$line" | sed 's/^  - \[[ x]\] //')
      local checked=$(echo "$line" | grep -o '\[x\]' || echo "")
      local status="open"

      # Determine priority from phase number
      local priority=""
      case "$phase" in
        1|2|3|4) priority="P0" ;;
        5|6|7) priority="P1" ;;
        8|9|10) priority="P2" ;;
      esac

      local labels="phase-$phase,$priority,task"

      # Create issue (skip if title already exists)
      local existing_title="[Phase $phase] $task"
      local existing=$(gh issue list --repo "$GITHUB_REPO" --state all --limit 100 2>/dev/null | grep "^$existing_title" | wc -l)
      if [ -n "$existing" ] && [ "$existing" -eq 0 ] 2>/dev/null; then
        if [ -n "$checked" ]; then
          gh issue create \
            --repo "$GITHUB_REPO" \
            --title "$existing_title" \
            --body "$task" \
            --label "$labels" \
            --label "task" \
            --label "done" \
            2>/dev/null || true
        else
          gh issue create \
            --repo "$GITHUB_REPO" \
            --title "$existing_title" \
            --body "$task" \
            --label "$labels" \
            --label "task" \
            2>/dev/null || true
        fi
        ((task_count++))
      else
        ((skipped++))
      fi
    fi
  done < "$TASKS_FILE"

  echo -e "${GREEN}✅ Created $task_count new issues${NC}"
  [ "$skipped" -gt 0 ] && echo -e "${YELLOW}⏭️  Skipped $skipped existing issues${NC}"
}

# List tasks
cmd_list() {
  check_gh
  local filter_phase="$1"

  if [ -n "$filter_phase" ]; then
    echo -e "${BLUE}Phase $filter_phase tasks:${NC}"
    gh issue list \
      --repo "$GITHUB_REPO" \
      --label "phase-$filter_phase" \
      --state all \
      --limit 100 \
      --json number,title,state,labels \
      --jq '.[] | "\(.state | if . == "OPEN" then "○" else "●" end) #\(.number): \(.title)"'
  else
    echo -e "${BLUE}All open tasks:${NC}"
    gh issue list \
      --repo "$GITHUB_REPO" \
      --label "task" \
      --state open \
      --limit 100 \
      --json number,title,labels \
      --jq '.[] | "[\(.labels | join(","))] #\(.number): \(.title)"'
  fi
}

# Show status
cmd_status() {
  check_gh

  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}🌊 MiniMax Agent — Task Progress${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  local total=$(gh issue list --repo "$GITHUB_REPO" --label "task" --state all --limit 300 2>/dev/null | wc -l | tr -d ' ')
  local open=$(gh issue list --repo "$GITHUB_REPO" --label "task" --state open --limit 300 2>/dev/null | wc -l | tr -d ' ')
  local closed=$(gh issue list --repo "$GITHUB_REPO" --label "task" --state closed --limit 300 2>/dev/null | wc -l | tr -d ' ')

  echo -e "${GREEN}Total:${NC}  $total"
  echo -e "${GREEN}Open:${NC}   $open"
  echo -e "${GREEN}Done:${NC}    $closed"
  echo ""

  # Per-phase breakdown
  echo -e "${YELLOW}By Phase:${NC}"
  for p in 1 2 3 4 5 6 7 8 9 10; do
    local phase_total=$(gh issue list --repo "$GITHUB_REPO" --label "phase-$p" --label "task" --state all --limit 100 2>/dev/null | wc -l | tr -d ' ')
    local phase_done=$(gh issue list --repo "$GITHUB_REPO" --label "phase-$p" --label "task" --state closed --limit 100 2>/dev/null | wc -l | tr -d ' ')
    local phase_open=$(gh issue list --repo "$GITHUB_REPO" --label "phase-$p" --label "task" --state open --limit 100 2>/dev/null | wc -l | tr -d ' ')
    local pct=0
    if [ "$phase_total" -gt 0 ]; then
      pct=$((phase_done * 100 / phase_total))
    fi
    printf "  Phase %2d: %3d%% (%d/%d done, %d open)\n" "$p" "$pct" "$phase_done" "$phase_total" "$phase_open"
  done

  echo ""
  echo -e "${YELLOW}By Priority:${NC}"
  for p in P0 P1 P2; do
    local p_total=$(gh issue list --repo "$GITHUB_REPO" --label "$p" --label "task" --state all --limit 100 2>/dev/null | wc -l | tr -d ' ')
    local p_done=$(gh issue list --repo "$GITHUB_REPO" --label "$p" --label "task" --state closed --limit 100 2>/dev/null | wc -l | tr -d ' ')
    echo "  $p: $p_done/$p_total done"
  done
}

# Show next P0 task
cmd_next() {
  check_gh

  echo -e "${BLUE}Next P0 task to work on:${NC}"
  gh issue list \
    --repo "$GITHUB_REPO" \
    --label "P0" \
    --label "task" \
    --state open \
    --sort created \
    --limit 1 \
    --json number,title,body,labels \
    --jq '.[0] | "## #\(.number): \(.title)\n\(.body // "")\nLabels: \(.labels | join(", "))"'
}

# Claim a task
cmd_claim() {
  check_gh
  local task_id="$1"

  if [ -z "$task_id" ]; then
    echo -e "${RED}❌ Usage: claim <task-id>${NC}"
    exit 1
  fi

  gh issue comment \
    --repo "$GITHUB_REPO" \
    "$task_id" \
    --body "Claimed for review. Working on this now." \
    2>/dev/null

  gh issue edit \
    --repo "$GITHUB_REPO" \
    "$task_id" \
    --add-label "in-progress" \
    2>/dev/null

  echo -e "${GREEN}✅ Claimed issue #$task_id${NC}"
}

# Complete a task
cmd_complete() {
  check_gh
  local task_id="$1"

  if [ -z "$task_id" ]; then
    echo -e "${RED}❌ Usage: complete <task-id>${NC}"
    exit 1
  fi

  gh issue close \
    --repo "$GITHUB_REPO" \
    "$task_id" \
    2>/dev/null

  gh issue edit \
    --repo "$GITHUB_REPO" \
    "$task_id" \
    --remove-label "in-progress" \
    --add-label "done" \
    2>/dev/null

  echo -e "${GREEN}✅ Closed issue #$task_id${NC}"
}

# Show remaining P0 tasks
cmd_remaining() {
  check_gh

  echo -e "${RED}Remaining P0 tasks:${NC}"
  gh issue list \
    --repo "$GITHUB_REPO" \
    --label "P0" \
    --label "task" \
    --state open \
    --sort created \
    --limit 50 \
    --json number,title \
    --jq '.[] | "- [#\(.number)] \(.title)"'
}

# Generate markdown report
cmd_report() {
  check_gh

  local report="# MiniMax Agent — Progress Report\n\n"
  report+="Generated: $(date)\n\n"

  # Overall stats
  local total=$(gh issue list --repo "$GITHUB_REPO" --label "task" --state all --limit 300 2>/dev/null | wc -l | tr -d ' ')
  local done=$(gh issue list --repo "$GITHUB_REPO" --label "task" --state closed --limit 300 2>/dev/null | wc -l | tr -d ' ')
  local pct=0
  if [ "$total" -gt 0 ]; then
    pct=$((done * 100 / total))
  fi

  report+="## Overall: $pct% ($done/$total tasks)\n\n"
  report+="| Phase | Focus | Done | Total | Progress |\n"
  report+="|-------|-------|------|-------|----------|\n"

  local phases=("Project Setup" "Core Chat" "API Integration" "Agentic Coding" "Floating Ball" "Settings" "Native macOS" "Performance" "Testing" "Distribution")

  for p in 1 2 3 4 5 6 7 8 9 10; do
    local phase_total=$(gh issue list --repo "$GITHUB_REPO" --label "phase-$p" --label "task" --state all --limit 100 2>/dev/null | wc -l | tr -d ' ')
    local phase_done=$(gh issue list --repo "$GITHUB_REPO" --label "phase-$p" --label "task" --state closed --limit 100 2>/dev/null | wc -l | tr -d ' ')
    local ppct=0
    if [ "$phase_total" -gt 0 ]; then
      ppct=$((phase_done * 100 / phase_total))
    fi
    report+="| $p | ${phases[$p-1]} | $phase_done | $phase_total | $ppct% |\n"
  done

  report+="\n## Remaining P0 Tasks\n\n"
  report+=$(gh issue list --repo "$GITHUB_REPO" --label "P0" --label "task" --state open --limit 20 --json number,title --jq '.[] | "- [#\(.number)] \(.title)"' 2>/dev/null || echo "None")

  echo -e "$report"
}

# Main
COMMAND="${1:-}"
shift || true

case "$COMMAND" in
  init) cmd_init "$@" ;;
  list) cmd_list "$@" ;;
  status) cmd_status ;;
  next) cmd_next ;;
  claim) cmd_claim "$@" ;;
  complete) cmd_complete "$@" ;;
  remaining) cmd_remaining ;;
  report) cmd_report ;;
  *) usage ;;
esac
