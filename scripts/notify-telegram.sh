#!/bin/bash
# 🌊 MiniMax Agent — Telegram Progress Notification
# Sends phase completion status to Telegram

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Telegram config from OpenClaw
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-8064947491:AAFP2rBtBZAKrXy_C0cQ5QM7RqaqiIPje9w}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-1618533723}"
TELEGRAM_API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"

send_message() {
    local message="$1"
    curl -s "$TELEGRAM_API/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "text=$message" \
        -d "parse_mode=Markdown" > /dev/null
}

# Get current status
get_status() {
    cd "$REPO_DIR"
    local total=$(gh issue list --repo wmehanna/minimax-agent --label "task" --state all --limit 500 2>/dev/null | wc -l | tr -d ' ')
    local done=$(gh issue list --repo wmehanna/minimax-agent --label "task" --state closed --limit 500 2>/dev/null | wc -l | tr -d ' ')
    local open=$(gh issue list --repo wmehanna/minimax-agent --label "task" --state open --limit 500 2>/dev/null | wc -l | tr -d ' ')
    local pct=0
    if [ "$total" -gt 0 ]; then
        pct=$((done * 100 / total))
    fi
    echo "$total|$done|$open|$pct"
}

# Check if phase completed
check_phase_complete() {
    local phase="$1"
    local total=$(gh issue list --repo wmehanna/minimax-agent --label "phase-$phase" --label "task" --state all --limit 200 2>/dev/null | wc -l | tr -d ' ')
    local done=$(gh issue list --repo wmehanna/minimax-agent --label "phase-$phase" --label "task" --state closed --limit 200 2>/dev/null | wc -l | tr -d ' ')
    local pct=0
    if [ "$total" -gt 0 ]; then
        pct=$((done * 100 / total))
    fi
    echo "$total|$done|$pct"
}

# Send status update
send_status() {
    local status=$(get_status)
    IFS='|' read -r total done open pct <<< "$status"

    local message="🌊 *MiniMax Agent Progress*

📊 *Overall:* $pct% ($done/$total tasks)

"

    # Per-phase breakdown
    local phases=("Project Setup" "Core Chat" "API Integration" "Agentic Coding" "Floating Ball" "Settings" "Native macOS" "Performance" "Testing" "Distribution")

    for p in 1 2 3 4 5 6 7 8 9 10; do
        local phase_status=$(check_phase_complete $p)
        IFS='|' read -r ptotal pdone ppct <<< "$phase_status"
        if [ "$ptotal" -gt 0 ]; then
            local bar=""
            local filled=$((ppct / 10))
            for i in $(seq 1 10); do
                if [ "$i" -le "$filled" ]; then
                    bar="${bar}🟦"
                else
                    bar="${bar}⬜"
                fi
            done
            message="${message}*Phase $p* (${phases[$p-1]}): ${bar} ${ppct}%

"
        fi
    done

    message="${message}

🔗 github.com/wmehanna/minimax-agent"

    send_message "$message"
}

# Send phase completion
send_phase_complete() {
    local phase="$1"
    local phase_status=$(check_phase_complete $phase)
    IFS='|' read -r ptotal pdone ppct <<< "$phase_status"

    local phases=("Project Setup" "Core Chat" "API Integration" "Agentic Coding" "Floating Ball" "Settings" "Native macOS" "Performance" "Testing" "Distribution")

    local message="🎉 *Phase $p Complete!*

*${phases[$p-1]}*
All $ptotal tasks done!

✅ github.com/wmehanna/minimax-agent"

    send_message "$message"
}

COMMAND="${1:-status}"
shift || true

case "$COMMAND" in
    status) send_status ;;
    phase-complete) send_phase_complete "$1" ;;
    *) echo "Usage: $0 [status|phase-complete <phase>]" ;;
esac
