#!/bin/bash
export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH

BOT_TOKEN="8064947491:AAFP2rBtBZAKrXy_C0cQ5QM7RqaqiIPje9w"
CHAT_ID="1618533723"
REPO="lucid-fabrics/minimax-agent"
MAIN_REPO="$HOME/git/minimax-agent"
TAG="[Hackintosh VM 102 - minimax-agent]"
WORKER="${WORKER_ID:-1}"

tg() { curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" --data-urlencode "chat_id=${CHAT_ID}" --data-urlencode "text=$1" > /dev/null; }

# 1. Find next unclaimed issue
ISSUE_JSON=$(gh issue list --repo "$REPO" --label task --state open --limit 50 --json number,title,body,labels 2>/dev/null | \
  python3 -c "
import json,sys
issues=json.load(sys.stdin)
unclaimed=sorted([i for i in issues if not any(l['name'] in ['in-progress','build-failed'] for l in i['labels'])], key=lambda x: x['number'])
print(json.dumps(unclaimed[0]) if unclaimed else '{}')
")

if [ "$ISSUE_JSON" = "{}" ]; then
  tg "$TAG All tasks complete."
  exit 0
fi

N=$(echo "$ISSUE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['number'])")
T=$(echo "$ISSUE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['title'])")
B=$(echo "$ISSUE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('body','') or 'See issue title.')")

# 2. Claim
gh issue edit "$N" --repo "$REPO" --add-label in-progress 2>/dev/null || true
tg "$TAG Worker $WORKER starting #$N: $T"

# 3. Isolated git worktree
WORKTREE="/tmp/mm-worker-${WORKER}-issue-${N}"
rm -rf "$WORKTREE"
cd "$MAIN_REPO"
git fetch origin main
git config user.name "MiniMax-Agent"
git config user.email "agent@minimax.ai"
git push origin --delete "issue-$N" 2>/dev/null || true
git branch -D "issue-$N" 2>/dev/null || true
git worktree add "$WORKTREE" -b "issue-$N" origin/main
cd "$WORKTREE"
git config user.name "MiniMax-Agent"
git config user.email "agent@minimax.ai"

# 4. Implement via agent
PROMPT="Implement this Swift feature. Write files in ${WORKTREE}/Sources/MiniMaxAgent/. Do not modify project files, scripts, or Package.swift. Do not run builds.

Issue #${N}: ${T}

${B}"

openclaw agent --agent main -m "$PROMPT" --timeout 300 2>&1 | tail -20 || true

# 5. Merge main + regenerate pbxproj to resolve conflicts
git fetch origin main
if ! git merge origin/main --no-edit 2>/dev/null; then
  xcodegen generate 2>/dev/null || true
  git add MiniMaxAgent.xcodeproj 2>/dev/null || true
  git diff --name-only --diff-filter=U | grep -v xcodeproj | xargs -I{} git checkout --ours {} 2>/dev/null || true
  git add -A
  GIT_EDITOR=true git merge --continue 2>/dev/null || git merge --abort
fi
xcodegen generate 2>/dev/null || true

# 6. Build
BUILD_OUTPUT=$(xcodebuild -project MiniMaxAgent.xcodeproj -scheme MiniMaxAgent -configuration Debug build 2>&1)
if ! echo "$BUILD_OUTPUT" | grep -q "BUILD SUCCEEDED"; then
  gh issue edit "$N" --repo "$REPO" --remove-label in-progress --add-label build-failed 2>/dev/null || true
  tg "$TAG Worker $WORKER build failed #$N: $T"
  git worktree remove "$WORKTREE" --force 2>/dev/null || true
  exit 1
fi

# 7. Commit + push
git add -A
if git diff --cached --quiet; then
  tg "$TAG Worker $WORKER: no changes committed for #$N — closing."
  gh issue edit "$N" --repo "$REPO" --remove-label in-progress 2>/dev/null || true
  git worktree remove "$WORKTREE" --force 2>/dev/null || true
  exit 0
fi
git commit -m "feat: $T"
git push origin "issue-$N"

# 8. PR + merge + close
gh pr create --base main --title "feat: $T" --body "Closes #$N" --repo "$REPO"
gh pr merge --squash --delete-branch
gh issue close "$N" --repo "$REPO" 2>/dev/null || true
git worktree remove "$WORKTREE" --force 2>/dev/null || true
tg "$TAG Worker $WORKER done #$N: $T"
