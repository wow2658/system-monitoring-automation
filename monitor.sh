#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
AGENT_LOG_DIR=/var/log/agent-app
LOG_FILE=$AGENT_LOG_DIR/monitor.log
NOW=$(date "+%Y-%m-%d %H:%M:%S")

# 1. 프로세스 생존 점검
# (주의: 실제 앱 실행 방식이 python3 agent_app.py 라면 아래와 같이 구체적으로 타겟팅)
PID=$(pgrep -f "agent.*app" | head -n 1)

if [ -z "$PID" ]; then 
    # [수정] 조용히 죽지 않고, 장애 발생 시점을 로그로 남긴 후 종료
    echo "[$NOW] [CRITICAL] 프로세스 사망 (PID Not Found). 모니터링 중단." >> $LOG_FILE
    exit 1
fi

# 2. 포트 바인딩 점검
# [수정] netstat 대신 최신 리눅스 표준인 ss 명령어 사용
if ! ss -tuln | grep -q ":15034"; then 
    echo "[$NOW] [CRITICAL] 15034 포트 단절 (Port Down). 모니터링 중단." >> $LOG_FILE
    exit 1
fi

# 3. 방화벽 점검 (경고)
WARN_MSG=""
if ! ufw status 2>/dev/null | grep -qw "active"; then 
    WARN_MSG="$WARN_MSG [WARNING: UFW Inactive]"
fi

# 4. 자원 수집
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
MEM_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100)}')
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

# 5. 임계값 경고
if [ $(echo "$CPU_USAGE > 20" | bc -l) -eq 1 ]; then WARN_MSG="$WARN_MSG [WARNING: CPU High]"; fi
if [ "$MEM_USAGE" -gt 10 ]; then WARN_MSG="$WARN_MSG [WARNING: MEM High]"; fi
if [ "$DISK_USAGE" -gt 80 ]; then WARN_MSG="$WARN_MSG [WARNING: DISK High]"; fi

# 6. 관제 데이터 누적
echo "[$NOW] PID:$PID CPU:${CPU_USAGE}% MEM:${MEM_USAGE}% DISK_USED:${DISK_USAGE}% $WARN_MSG" >> $LOG_FILE