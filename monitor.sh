#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
AGENT_LOG_DIR=/var/log/agent-app
LOG_FILE=$AGENT_LOG_DIR/monitor.log
NOW=$(date "+%Y-%m-%d %H:%M:%S")

# Health Check
PID=$(pgrep -f agent-app | head -n 1)
if [ -z "$PID" ]; then exit 1; fi
if ! netstat -tuln | grep -q ":15034"; then exit 1; fi

# 방화벽 점검 (선택)
WARN_MSG=""
if ! ufw status 2>/dev/null | grep -qw "active"; then WARN_MSG="$WARN_MSG [WARNING: UFW Inactive]"; fi

# 자원 수집
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
MEM_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100)}')
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

# 임계값 경고
if [ $(echo "$CPU_USAGE > 20" | bc -l) -eq 1 ]; then WARN_MSG="$WARN_MSG [WARNING: CPU High]"; fi
if [ "$MEM_USAGE" -gt 10 ]; then WARN_MSG="$WARN_MSG [WARNING: MEM High]"; fi
if [ "$DISK_USAGE" -gt 80 ]; then WARN_MSG="$WARN_MSG [WARNING: DISK High]"; fi

echo "[$NOW] PID:$PID CPU:${CPU_USAGE}% MEM:${MEM_USAGE}% DISK_USED:${DISK_USAGE}% $WARN_MSG" >> $LOG_FILE