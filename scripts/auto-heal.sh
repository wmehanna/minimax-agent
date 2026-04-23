#!/bin/bash
# auto-heal.sh — OpenClaw gateway health monitor and auto-restart
# Run via launchd or cron every 5 minutes

LOG_DIR="${HOME}/.openclaw"
LOG_FILE="${LOG_DIR}/openclaw-$(date +%Y-%m-%d).log"
PID_FILE="${LOG_DIR}/gateway.pid"
MAX_LOG_SIZE=$((500 * 1024 * 1024))  # 500MB

health_check() {
    # Check if gateway is responsive
    timeout 5 openclaw cron list >/dev/null 2>&1
    return $?
}

rotate_log_if_needed() {
    if [ -f "$LOG_FILE" ]; then
        SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null)
        if [ "$SIZE" -gt "$MAX_LOG_SIZE" ]; then
            echo "$(date): Rotating log (size: $SIZE)" >> "${LOG_FILE}.rotate.log"
            : > "$LOG_FILE"
        fi
    fi
}

restart_gateway() {
    echo "$(date): Gateway unhealthy, restarting..." >> "$LOG_FILE"
    openclaw gateway restart >> "$LOG_FILE" 2>&1
    sleep 3
    if health_check; then
        echo "$(date): Gateway restarted successfully" >> "$LOG_FILE"
    else
        echo "$(date): Gateway restart failed" >> "$LOG_FILE"
    fi
}

# Main
rotate_log_if_needed

if ! health_check; then
    restart_gateway
fi
