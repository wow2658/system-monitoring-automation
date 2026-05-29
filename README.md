# 시스템 관제 자동화 미션 수행 내역서

## 1. 리눅스 실습 환경 구축 (Docker)

- **도입 배경 (Why?):** 호스트 OS(Windows/Mac) 환경을 훼손하지 않고 독립적이고 안전한 Ubuntu 22.04 서버 환경을 구축하기 위해 도커(Docker) 컨테이너를 사용합니다. 방화벽(UFW) 및 시스템 서비스 제어를 위해 `--privileged` 옵션을 부여하고, 요구사항에 명시된 필수 포트(20022, 15034)를 포워딩합니다. 또한 호스트에 있는 제공 앱(`agent-app-linux-x86`)을 컨테이너 내부로 안전하게 복사하여 실습 준비를 마칩니다.
- **실행 명령어:**

```bash
# 1. 필수 포트 매핑 및 시스템 권한을 포함한 컨테이너 생성 후 접속
docker run -it --privileged -p 20022:20022 -p 15034:15034 --name agent-server-real ubuntu:22.04 /bin/bash

# 2. (호스트 PC의 새 터미널 창에서) 제공된 애플리케이션을 컨테이너 내부로 복사
docker cp agent-app-linux-x86 agent-server-real:/root/agent-app
```

- **수행 증거 (도커 컨테이너 구동 및 접속 확인):**
  ![도커 환경 구축](https://github.com/user-attachments/assets/9179b84a-e0b7-44cd-94fa-767242be7a2a)
  ![컨테이너 내부로 복사](https://github.com/user-attachments/assets/9b796d56-d873-47ba-bb07-d025a20274da)

## 2. 기본 보안 및 네트워크 설정

### 2-0. 필수 패키지 설치 (Docker 환경 사전 준비)

- **도입 배경 (Why?):** 도커의 Ubuntu 기본 이미지는 최소한의 기능만 포함된 깡통 상태입니다. 따라서 설정과 네트워크 통제에 필요한 SSH 서버, 방화벽(UFW), 네트워크 확인 툴, ACL, 그리고 관리자 권한 도구(`sudo`)를 먼저 설치해야 합니다.
- **실행 명령어:**

```bash
# 패키지 목록 업데이트 및 필수 패키지 일괄 설치
apt update
apt install sudo openssh-server ufw net-tools acl -y
```

### 2-1. SSH 포트 변경 및 Root 원격 접속 차단

- **도입 배경 (Why?):** 기본 SSH 포트(22)를 그대로 방치할 경우, 악성 봇(Bot)들에 의한 무작위 대입 공격의 표적이 됩니다. 포트를 `20022`로 변경하여 1차 스캔을 회피하고, 최고 관리자(`root`)의 원격 로그인을 차단하여 계정 탈취 시 발생할 수 있는 시스템 파괴 리스크를 방어합니다.
- **실행 명령어:**

```bash
# SSH 설정 파일 수정 (포트 변경 및 루트 접속 차단)
sudo sed -i 's/#Port 22/Port 20022/g' /etc/ssh/sshd_config
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' /etc/ssh/sshd_config

# SSH 서비스 시작 (Docker 환경에서는 systemctl 대신 service 명령어 사용)
sudo service ssh start

# 포트 리슨 상태 확인 (20022 포트 확인)
sudo netstat -tulnp | grep ssh
```

- **수행 증거 (20022 포트 Listen 확인):**
  ![SSH 포트 변경](https://github.com/user-attachments/assets/9d58621b-d08f-436d-965b-a27c13348b48)

### 2-2. 방화벽(UFW) 설정

- **도입 배경 (Why?):** 서버 내부의 취약한 서비스가 외부로 노출되는 것을 막기 위해, 시스템을 거대한 성벽으로 둘러싸고(Default Deny) 검증된 안전한 출입구(SSH, APP) 딱 두 개만 개방(Allow)하는 '제로 트러스트' 네트워크 접근 통제를 수행합니다.
- **실행 명령어:**

```bash
# 기본 인바운드 차단 및 특정 포트 허용
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 20022/tcp
sudo ufw allow 15034/tcp

# 방화벽 활성화 및 상태 확인
sudo ufw --force enable
sudo ufw status
```

- **수행 증거 (UFW Active 및 20022, 15034 포트 허용 확인):**
  ![방화벽 설정](https://github.com/user-attachments/assets/da029268-0e75-4f14-b2f3-3358210c4934)

## 3. 계정/그룹/권한 체계 구축 (협업 + 최소 권한)

- **도입 배경 (Why?):** 다중 사용자 환경에서 모든 권한을 공유하면, 보안 수준이 낮은 계정이 침해당했을 때 핵심 서버 키나 로그가 유출될 위험이 큽니다. 따라서 역할(Role) 기반으로 그룹을 쪼개고, **ACL(접근 제어 목록)**을 통해 특정 폴더(`api_keys`, `log`)에는 핵심 인력(`core` 그룹)만 접근할 수 있도록 최소 권한의 원칙을 적용합니다.

### 3-1. 계정 및 그룹 구성

- **그룹 설계:** `agent-common`(전체 인원), `agent-core`(운영/개발 인원)
- **실행 명령어:**

```bash
# 그룹 생성
sudo groupadd agent-common
sudo groupadd agent-core

# 계정 생성 및 그룹 할당
sudo useradd -m -s /bin/bash -G agent-common,agent-core agent-admin
sudo useradd -m -s /bin/bash -G agent-common,agent-core agent-dev
sudo useradd -m -s /bin/bash -G agent-common agent-test

# 할당 내역 검증
id agent-admin && id agent-dev && id agent-test
```

- **수행 증거 (생성된 계정 및 그룹 할당 내역):**
  ![계정 및 그룹](https://github.com/user-attachments/assets/1eebce45-b409-4548-abc8-76ef535249d4)

### 3-2. 디렉토리 구조 및 ACL 권한 설정

- **접근 정책:** - `upload_files`: `agent-common` 그룹 전체 R/W 허용 (공유 폴더)
  - `api_keys` 및 `log`: `agent-core` 그룹 전용 R/W 허용 (보안 폴더, test 계정 접근 불가)
- **실행 명령어:**

```bash
# 기본 디렉토리 뼈대 생성 (agent-admin 홈 디렉토리 기준)
sudo mkdir -p /home/agent-admin/agent-app/upload_files
sudo mkdir -p /home/agent-admin/agent-app/api_keys
sudo mkdir -p /var/log/agent-app

# 소유 그룹 변경
sudo chown root:agent-core /home/agent-admin/agent-app/api_keys /var/log/agent-app

# ACL 자물쇠 채우기 및 권한 검증
sudo setfacl -m g:agent-core:rwx /home/agent-admin/agent-app/api_keys
getfacl /home/agent-admin/agent-app/api_keys
```

- **수행 증거 (디렉토리 소유권 및 ACL 세부 설정 내역):**
  ![ACL 설정](https://github.com/user-attachments/assets/1bbab4c6-f72d-4173-bc6b-22109ffe462b)

## 4. 환경 변수 설정 및 보안 키 생성

**도입 배경 (Why?):** 애플리케이션 실행 시 포트 번호, 파일 경로 등을 소스코드에 하드코딩(Hard-coding)하면 보안 및 유지보수에 취약합니다. 환경 변수(Environment Variables)를 통해 동적으로 경로를 관리하고, 서비스 동작에 필수적인 API 암호화 키를 생성하여 최소 권한을 부여합니다.

### 4-1. 환경 변수 영구 등록 (.bashrc)

**실행 명령어:**
_(주의: `root` 계정이 아닌 `agent-admin` 계정으로 전환 후 실행해야 합니다.)_

```bash
# agent-admin 계정으로 전환
su - agent-admin

# 환경 변수 추가 (주의: AGENT_KEY_PATH는 파일명이 아닌 디렉토리 경로까지만 지정)
echo 'export AGENT_HOME=/home/agent-admin/agent-app' >> ~/.bashrc
echo 'export AGENT_PORT=15034' >> ~/.bashrc
echo 'export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files' >> ~/.bashrc
echo 'export AGENT_KEY_PATH=$AGENT_HOME/api_keys' >> ~/.bashrc
echo 'export AGENT_LOG_DIR=/var/log/agent-app' >> ~/.bashrc

# 현재 쉘 세션에 즉시 반영 및 검증
source ~/.bashrc
env | grep AGENT
```

**수행 증거 (환경 변수 적용 내역):**
![환경 변수 설정](https://github.com/user-attachments/assets/a90ecc6b-c31d-4d0d-a342-a36085af1a4e)

### 4-2. API 인증용 비밀 키 파일 생성

**실행 명령어:**

```bash
# 앱 요구사항에 맞춘 파일명(secret.key)으로 키 생성 및 내용 입력
echo "agent_api_key_test" > $AGENT_KEY_PATH/secret.key

# 외부 유저 접근 차단 (640 권한 부여)
chmod 640 $AGENT_KEY_PATH/secret.key

# 내용 및 권한 검증
cat $AGENT_KEY_PATH/secret.key
ls -l $AGENT_KEY_PATH/secret.key
```

**수행 증거 (비밀 키 파일 생성 및 권한 확인):**
![키 파일 생성](https://github.com/user-attachments/assets/aa296ae1-41d8-4da2-900b-f2d34a1e08fe)

---

## 5. Agent App 백그라운드 실행 및 트러블슈팅 조치

**도입 배경 (Why?):** 구성된 환경 변수와 키 파일을 바탕으로 애플리케이션을 실행합니다. 이를 위해 호스트에서 복사해 둔 앱 실행 파일을 올바른 위치로 이동시키고, 로그 디렉토리의 쓰기 권한을 부여하는 선행 작업이 필수적입니다. 이후 터미널 창을 닫아도 서비스가 종료되지 않도록 백그라운드(`&`)로 실행합니다.

**실행 명령어:**

```bash
# 0. 필수 파일 복사 및 권한 부여 (root 계정에서 수행 필수)
# (현재 agent-admin 계정이라면 exit 명령어로 잠시 root로 빠져나옵니다.)
exit

# 로그 폴더 소유권 변경
chown -R agent-admin:agent-core /var/log/agent-app

# 앱 실행 파일을 정상 경로로 이동 및 소유권/실행 권한(750) 부여
cp /root/agent-app /home/agent-admin/agent-app/agent-app
chown agent-admin:agent-core /home/agent-admin/agent-app/agent-app
chmod 750 /home/agent-admin/agent-app/agent-app

# 권한 세팅 완료 후 다시 서비스 계정으로 접속합니다.
su - agent-admin

# 1. 앱 구동 스크립트 실행 (환경 변수와 백그라운드 실행 적용)
$AGENT_HOME/agent-app > $AGENT_LOG_DIR/agent_app.log 2>&1 &

# 2. 부팅 로그 확인 (All Boot Checks Passed 확인)
cat $AGENT_LOG_DIR/agent_app.log

# 3. 15034 포트 Listen 확인 (netstat 사용)
netstat -tuln | grep 15034
```

**수행 증거 (앱 Boot 결과 및 포트 Listen 상태):**
![앱 실행 결과](https://github.com/user-attachments/assets/7d874c33-9ca7-4820-bbb7-4054a82348bb)

---

## 6. 시스템 관제 자동화 스크립트 (monitor.sh)

- **도입 배경 (Why?):** 서비스 고가용성(HA)을 위해 앱의 상태(PID, 포트)와 서버 자원(CPU, MEM, DISK)을 주기적으로 점검하고, 임계치 초과 시 경고를 기록하는 스크립트를 작성합니다. 개발 인력(`agent-dev`)이 관리하도록 소유권을 분리합니다.

- **실행 명령어:**
  _(현재 `agent-admin` 상태에서 진행합니다.)_

```bash
# 1. 계산식 처리를 위한 패키지 설치 (root 계정에서 수행 필수)
# (현재 agent-admin 계정이라면 exit 명령어로 잠시 root로 빠져나옵니다.)
exit
apt update
apt install bc sysstat -y

# 상위 폴더(agent-app)의 소유권을 변경하여 하위 폴더(bin) 생성 권한을 확보합니다.
chown agent-admin:agent-core /home/agent-admin/agent-app

# 다시 서비스 계정으로 접속합니다.
su - agent-admin

# 2. 스크립트 작성 디렉토리 생성
mkdir -p $AGENT_HOME/bin

# 3. monitor.sh 스크립트 작성
cat << 'EOF' > $AGENT_HOME/bin/monitor.sh
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
AGENT_LOG_DIR=/var/log/agent-app
LOG_FILE=$AGENT_LOG_DIR/monitor.log
NOW=$(date "+%Y-%m-%d %H:%M:%S")

# Health Check
PID=$(pgrep -f agent-app)
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
EOF

# 4. 소유권 및 권한 설정 (개발자 소유, 핵심그룹 읽기/실행, 외부 차단)
# 소유권 변경(chown)은 root 권한이 필요하므로 잠시 root로 이동하여 처리 후 복귀합니다.
exit
chown agent-dev:agent-core /home/agent-admin/agent-app/bin/monitor.sh
chmod 750 /home/agent-admin/agent-app/bin/monitor.sh

# 설정이 완료되었으므로 다시 agent-admin으로 접속합니다.
su - agent-admin

# 5. 수동 테스트 실행 (권한이 정상적으로 작동하는지 확인)
# 주의: 이 스크립트는 이제 agent-dev 소유이고 agent-core 그룹만 실행 가능합니다.
# 현재 agent-admin은 agent-core 그룹에 속해 있으므로 정상 실행되어야 합니다.
$AGENT_HOME/bin/monitor.sh
cat $AGENT_LOG_DIR/monitor.log
```

- **수행 증거 (스크립트 1회 수동 실행 후 로그 파일 확인):**
  ![스크립트 수행 결과](https://github.com/user-attachments/assets/13ab7520-05bd-4d23-aa03-acc4b079ef41)

---

## 7. Cron 자동화 및 Logrotate 구성

- **도입 배경 (Why?):** 작성된 모니터링 스크립트를 관리자의 개입 없이 24시간 백그라운드에서 매 분마다 실행되도록 `cron` 스케줄러에 등록합니다. 또한, 방대한 로그가 디스크를 가득 채우지 않도록 `logrotate`를 통해 로그 파일을 순환 및 압축 관리합니다.

### 7-1. Cron 자동화

- **실행 명령어:**

```bash
# 0. 필수 데몬 및 에디터 설치 (root 계정에서 수행 필수)
# (현재 agent-admin 계정이라면 exit 명령어로 잠시 root로 빠져나옵니다.)
exit
apt update
apt install cron logrotate nano -y

# 1. cron 서비스 시작
service cron start

# 2. agent-admin 계정으로 다시 로그인하여 크론탭 편집
su - agent-admin

# (참고: 처음 crontab -e를 치면 에디터를 고르라고 나옵니다. 1번(nano)을 선택하세요.)
crontab -e

# 내 크론탭 스케줄 리스트 확인하기 (이제 아까 등록한 별 5개가 잘 보일 겁니다!)
crontab -l

# 1분마다 쌓이는 로그 10줄 확인하기 (아래 명령어를 그대로 복사해서 붙여넣으세요!)
tail -n 10 $AGENT_LOG_DIR/monitor.log

# 3. 편집기 최하단에 스케줄링 규칙 삽입 (매 분 실행) 후 컨O 엔터 컨X
* * * * * /home/agent-admin/agent-app/bin/monitor.sh
```

 **수행 증거 (Cron 누적 로그):**
  ![크론 결과](https://github.com/user-attachments/assets/1d5640f7-82d5-4d0e-a75b-5f6de1849543)

### 7-2. Logrotate 로그 관리 적용

- **실행 명령어:**
  _(root 계정 권한이 필요합니다. `exit`를 입력해 root로 전환하세요.)_

```bash
# 0. root 권한으로 복귀 (현재 agent-admin 계정 상태에서 빠져나옴)
exit

# 1. 설정 파일 생성
cat << 'EOF' > /etc/logrotate.d/agent-app
/var/log/agent-app/monitor.log {
    su agent-admin agent-core
    size 10M
    rotate 10
    compress
    missingok
    notifempty
    create 640 agent-admin agent-core
}
EOF

# 2. 수동 강제 실행 테스트 (정상 압축/회전 검증)
logrotate -f /etc/logrotate.d/agent-app
ls -l /var/log/agent-app
```

- **수행 증거 (Logrotate .gz 압축 파일 확인):**
  ![로그로테이트 결과](https://github.com/user-attachments/assets/904e50d9-1cb2-46f8-8661-f84870c341cd)
