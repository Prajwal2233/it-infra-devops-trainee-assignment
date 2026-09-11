#!/bin/bash
#############################################################################
# infra_health_check.sh
#
# Task 3: Automation & Shell Scripting
#
# Checks CPU / RAM / disk usage and Docker + app-container health.
# If disk usage > threshold OR the app container is stopped/missing,
# prints a [WARNING] and appends a timestamped entry to the log file.
#
# Deploy path : /opt/scripts/infra_health_check.sh
# Log file    : /var/log/infra_health.log
# Schedule    : every 15 minutes via cron (see cron/infra_health_check.cron)
#############################################################################

set -uo pipefail

LOG_FILE="/var/log/infra_health.log"
DISK_THRESHOLD=85
APP_CONTAINER_NAME="app"   # must match the container_name in docker-compose.yml
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

log_warning() {
    local message="$1"
    echo "[WARNING] ${message}"
    echo "${TIMESTAMP} [WARNING] ${message}" >> "$LOG_FILE"
}

# Make sure the log file exists and is writable (create if this is the first run)
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE" 2>/dev/null || { echo "ERROR: cannot write to ${LOG_FILE}. Run as root/sudo."; exit 1; }
fi

echo "===== Infra Health Check: ${TIMESTAMP} ====="

# ---------------------------------------------------------------------------
# CPU usage (% used, derived from idle time reported by 'top')
# ---------------------------------------------------------------------------
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk -F',' '{for(i=1;i<=NF;i++) if ($i ~ /id/) print $i}' | grep -o '[0-9.]*')
CPU_USAGE=$(awk "BEGIN {printf \"%.1f\", 100 - ${CPU_IDLE:-0}}")
echo "CPU Usage : ${CPU_USAGE}%"

# ---------------------------------------------------------------------------
# RAM usage
# ---------------------------------------------------------------------------
MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
MEM_PERCENT=$(awk "BEGIN {printf \"%.1f\", (${MEM_USED}/${MEM_TOTAL})*100}")
echo "RAM Usage : ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PERCENT}%)"

# ---------------------------------------------------------------------------
# Root disk usage
# ---------------------------------------------------------------------------
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
echo "Disk Usage (/) : ${DISK_USAGE}%"

# ---------------------------------------------------------------------------
# Docker service status
# ---------------------------------------------------------------------------
DOCKER_RUNNING=false
if systemctl is-active --quiet docker; then
    echo "Docker Service : RUNNING"
    DOCKER_RUNNING=true
else
    echo "Docker Service : STOPPED"
    log_warning "Docker service is not running."
fi

# ---------------------------------------------------------------------------
# App container status
# ---------------------------------------------------------------------------
if [ "$DOCKER_RUNNING" = true ]; then
    CONTAINER_STATE=$(docker inspect -f '{{.State.Running}}' "$APP_CONTAINER_NAME" 2>/dev/null || echo "not_found")
    if [ "$CONTAINER_STATE" = "true" ]; then
        echo "App Container (${APP_CONTAINER_NAME}) : RUNNING"
    elif [ "$CONTAINER_STATE" = "false" ]; then
        echo "App Container (${APP_CONTAINER_NAME}) : STOPPED"
        log_warning "Application container '${APP_CONTAINER_NAME}' exists but is stopped."
    else
        echo "App Container (${APP_CONTAINER_NAME}) : NOT FOUND"
        log_warning "Application container '${APP_CONTAINER_NAME}' was not found."
    fi
fi

# ---------------------------------------------------------------------------
# Disk threshold check
# ---------------------------------------------------------------------------
if [ "${DISK_USAGE:-0}" -ge "$DISK_THRESHOLD" ]; then
    log_warning "Disk usage is at ${DISK_USAGE}%, exceeding the ${DISK_THRESHOLD}% threshold."
fi

echo "===== Health Check Complete ====="
exit 0
