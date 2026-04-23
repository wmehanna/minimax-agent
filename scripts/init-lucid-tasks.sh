#!/bin/bash
# 🌊 MiniMax Agent — Generate Detailed Issues for lucid-fabrics
# Creates well-structured issues from macos_agent_tasks.md with full context

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TASKS_FILE="$REPO_DIR/macos_agent_tasks.md"
GITHUB_REPO="${GITHUB_REPO:-lucid-fabrics/minimax-agent}"

# Phase descriptions
PHASE_DESC[1]="Project Setup & Shell — XcodeGen, SPM, app entry point, entitlements"
PHASE_DESC[2]="Core Chat Interface — Window, sidebar, chat area, input, theme system"
PHASE_DESC[3]="API Integration — MiniMax API client, Claude API, model management, multimodal"
PHASE_DESC[4]="Agentic Coding Engine — Tool definitions, sandbox, task state machine, terminal, workspace"
PHASE_DESC[5]="Floating Ball Widget — Draggable floating button, mini chat, quick tools"
PHASE_DESC[6]="Preferences & Settings — Settings window, keychain, SQLite persistence"
PHASE_DESC[7]="Native macOS Integration — Menu bar, notifications, drag & drop, share extension, accessibility"
PHASE_DESC[8]="Performance & Reliability — Lazy loading, memory management, error handling, logging"
PHASE_DESC[9]="Testing & Quality — Unit tests, UI tests, CI/CD, code signing"
PHASE_DESC[10]="Distribution — App Store, notarization, DMG, Homebrew, Sparkle"

echo "🌊 Generating detailed issues for $GITHUB_REPO"

# Create labels first
echo "📋 Creating labels..."
for p in 1 2 3 4 5 6 7 8 9 10; do
  gh api repos/"$GITHUB_REPO"/labels/phase-$p --silent 2>/dev/null || \
  gh api repos/"$GITHUB_REPO"/labels --silent -F name="phase-$p" -F color="0e8a16" 2>/dev/null || true
done

for p in P0 P1 P2; do
  color="yellow"
  [[ "$p" == "P0" ]] && color="ff0000"
  [[ "$p" == "P1" ]] && color="fbca04"
  [[ "$p" == "P2" ]] && color="0e8a16"
  gh api repos/"$GITHUB_REPO"/labels/$p --silent 2>/dev/null || \
  gh api repos/"$GITHUB_REPO"/labels --silent -F name="$p" -F color="$color" 2>/dev/null || true
done

for label in task in-progress done needs-review; do
  gh api repos/"$GITHUB_REPO"/labels/$label --silent 2>/dev/null || \
  gh api repos/"$GITHUB_REPO"/labels --silent -F name="$label" -F color="5319e7" 2>/dev/null || true
done

echo "✅ Labels created"

# Parse tasks file and create detailed issues
current_phase=""
current_section=""
task_count=0

while IFS= read -r line; do
  # Phase header
  if [[ "$line" =~ ^##\ Phase\ ([0-9]+):\ (.+) ]]; then
    current_phase="${BASH_REMATCH[1]}"
    current_section="${BASH_REMATCH[2]}"
    continue
  fi

  # Section header (###)
  if [[ "$line" =~ ^###\ ([0-9]+\.[0-9]+)\  ]]; then
    current_section="${BASH_REMATCH[1]}"
    continue
  fi

  # Task line
  if echo "$line" | grep -qE '^  - \[[ x]\]\ '; then
    checked=$(echo "$line" | grep -o '\[x\]' || echo "")
    task=$(echo "$line" | sed 's/^  - \[[ x]\] //')

    # Skip already done tasks
    [[ -n "$checked" ]] && continue

    # Determine priority
    case "$current_phase" in
      1|2|3|4) priority="P0" ;;
      5|6|7) priority="P1" ;;
      *) priority="P2" ;;
    esac

    # Build detailed body
    body="## Context

Phase $current_phase: ${PHASE_DESC[$current_phase]}

Section: $current_section

## Task

$task

## Implementation Notes

- [ ] Implement this task
- [ ] Write tests if applicable
- [ ] Update documentation if needed
- [ ] Verify build passes

## Dependencies

<!-- List any tasks that must complete before this one -->

## Verification

How to verify this task is complete:
<!-- Describe what 'done' looks like for this task -->"

    labels="phase-$current_phase,$priority,task"

    # Check if issue already exists
    title="[Phase $current_phase] $task"
    existing=$(gh issue list --repo "$GITHUB_REPO" --state all --limit 100 --json title --jq ".[] | select(.title == \"$title\") | .title" 2>/dev/null || echo "")

    if [[ -z "$existing" ]]; then
      gh issue create \
        --repo "$GITHUB_REPO" \
        --title "$title" \
        --body "$body" \
        --label "$labels" \
        2>/dev/null && task_count=$((task_count + 1)) || true
    fi
  fi
done < "$TASKS_FILE"

echo ""
echo "✅ Created $task_count new detailed issues"
echo ""
echo "Next: run 'gh issue list --repo $GITHUB_REPO --label P0 --state open' to see P0 tasks"
