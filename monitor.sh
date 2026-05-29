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

# 4. 자원 수집 (시스템 명령어의 출력물에서 불필요한 문자를 제거하고 순수 '수치'만 정밀하게 파싱)

# [CPU 사용량 추출 원리]
# - 'top'은 윈도우의 작업 관리자처럼 프로세스와 CPU 점유율을 실시간으로 보여주는 독자적인 명령어임.
# - '-b'(Batch mode) 옵션은 스크립트가 화면을 읽을 수 없으므로, 번쩍번쩍 새로고침되는 실시간 화면을 텍스트 뭉치(기계가 읽을 수 있는 문자열)로 출력하라는 뜻임.
# - '-n1'(Iteration 1) 옵션은 딱 1번만 자원을 조회하고 top 명령어를 즉시 종료하라는 뜻으로, 이 옵션이 없으면 스크립트가 다음 단계로 넘어가지 못하고 영원히 대기(Hang) 상태에 빠짐.
# - 'us'(User, $2)는 우리가 띄운 agent-app이나 웹서버 같은 일반 프로그램이 쓴 CPU 비율이며, 'sy'(System, $4)는 리눅스 운영체제(커널) 자체가 시스템 처리를 위해 쓴 CPU 비율임.
# - 서버의 실제 총 부하량(Total Load)을 완벽히 파악하려면 이 두 가지 힘(us + sy)을 합산해야 하므로 awk 코드를 통해 두 값을 더한 순수 실수(소수점 포함) 수치만 추출함.
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')

# [MEMORY 사용량 추출 원리]
# - 'free'는 현재 시스템의 RAM(메모리) 상태(전체 용량, 사용량 등)를 보여주는 명령어임.
# - free 명령어는 결과를 퍼센트(%)가 아닌 십만, 백만 단위의 거대한 '킬로바이트(KB)' 수치로 뱉어내기 때문에, 스크립트 조건문이 "10% 초과" 같은 직관적인 비율로 판단하기 불가능함.
# - 따라서 엑셀 공식과 동일하게 (사용 중인 킬로바이트 수치 $3 / 전체 킬로바이트 수치 $2 * 100) 공식을 적용하여 메모리 점유율을 계산함.
# - 계산 후 후속 단계에서의 직관적인 정수 비교 연산을 위해 awk의 printf("%.0f") 기법을 사용하여 소수점을 깔끔하게 버리고 순수 정수(Integer) 형태로 데이터를 정제(Cleansing)함.
MEM_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100)}')

# [DISK 사용량 추출 원리]
# - 'df'는 'Disk Free(또는 Disk Filesystem)'의 약자로, 현재 서버의 하드디스크 남은 용량을 체크하는 독립적인 명령어임.
# - 'df /' 명령어를 실행하면 시스템 루트 가상 디스크의 '제목 줄'과 '데이터 줄' 딱 2줄만 화면에 출력됨.
# - 'tail -1' 명령어를 파이프(|)로 연결하여 제목 줄을 버리고 실제 용량 수치가 들어있는 맨 '마지막 줄(데이터 줄)'만 가져옴.
# - 그 상태에서 'awk {print $5}'로 5번째 칸에 위치한 디스크 사용률(Use%) 데이터만 쏙 뽑아낸 뒤, 뒤에 붙어있는 문자 '%'를 제거하지 않으면 bash 내부에서 정수 비교 시 문법 에러(Integer Expression Expected)가 나므로, 'sed s/%//' 명령어를 통해 '%' 기호를 강제로 암살하고 순수 숫자만 남김.
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')


# 5. 임계값 경고 (파싱된 숫자 데이터들을 기반으로 조건부 경고 메시지를 문자열에 누적시킴)

# [CPU 임계값 비교 원리]
# - 리눅스 bash 쉘의 기본 [ ] 조건문은 소수점이 포함된 '실수형(Float)' 데이터의 크기 비교 연산을 지원하지 못함.
# - 이를 해결하기 위해 파이프(|) 통로를 통해 리눅스 내장 소수점 계산기인 'bc -l'에 "CPU사용량 > 20"이라는 수식을 문장으로 넘겨 계산하게 만듦.
# - bc 계산기는 이 조건이 맞으면 참(1), 틀리면 거짓(0)을 뱉어내므로, 그 결과값이 1과 같은지(-eq, EQual) 우회하여 검증하는 고급 문법을 사용함.
if [ $(echo "$CPU_USAGE > 20" | bc -l) -eq 1 ]; then WARN_MSG="$WARN_MSG [WARNING: CPU High]"; fi

# [MEM / DISK 임계값 비교 원리]
# - 4단계 자원 수집 과정에서 이미 소수점과 문자%를 다 떼어내고 순수 '정수(Integer)' 형태로 예쁘게 정제해 두었음.
# - 따라서 리눅스 bash에서 꺾쇠(>) 기호는 파일 저장용 리다이렉션으로 이미 예약되어 사용할 수 없으므로, 숫자가 더 큰지(초과) 비교하는 전용 정수 비교 연산자인 '-gt'(Greater Than, ~보다 큰)를 사용하여 조건문 문법 에러 없이 완벽하고 직관적으로 처리함.
if [ "$MEM_USAGE" -gt 10 ]; then WARN_MSG="$WARN_MSG [WARNING: MEM High]"; fi
if [ "$DISK_USAGE" -gt 80 ]; then WARN_MSG="$WARN_MSG [WARNING: DISK High]"; fi


# 6. 관제 데이터 누적 (시계열 추적 및 수집기 연동을 고려한 로그 포맷팅)

# [중앙 집중형 로그 수집기 및 포맷 고정의 원리]
# - 실무 서버 운영 환경에서는 관리자가 수십, 수백 대의 서버에 일일이 들어가 로그 파일을 보지 않고, ELK(Logstash) 스택이나 Splunk 같은 '중앙 집중형 로그 수집기' 시스템을 구축해 한곳에서 모아봄.
# - 일기장처럼 줄바꿈을 많이 하거나 풀어서 쓰면 기계(로그 수집기)가 데이터를 파싱하지 못하므로, 규칙적인 'KEY:VALUE(이름표:값)' 구조를 유지하고 공백으로 칸을 구분한 단일 행(Single-line) 포맷으로 조립함.
# - 이렇게 짜두면 수집기 내부의 패턴 분석 기술(정규표현식, Regex)이 "CPU 짝꿍은 몇 번, MEM 짝꿍은 몇 번" 하고 숫자만 번개처럼 쏙쏙 빼가서 모니터링 웹 화면에 실시간 상태 변화 대시보드 그래프를 아주 예쁘게 그려줄 수 있음.
# - 과거부터 현재까지 서버 자원이 어떻게 변화했는지 히스토리(시계열 데이터)를 온전히 보존하기 위해, 파일을 덮어쓰는 기호('>')가 아닌 파일 맨 끝에 내용을 추가하여 누적하는 이어쓰기 리다이렉션 기호('>>')를 사용하여 관제 로그 파일에 영구 기록함.
echo "[$NOW] PID:$PID CPU:${CPU_USAGE}% MEM:${MEM_USAGE}% DISK_USED:${DISK_USAGE}% $WARN_MSG" >> $LOG_FILE