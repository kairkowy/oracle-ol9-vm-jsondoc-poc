# 2. 공통 Oracle Linux 9 준비

VM1과 VM2에서 root로 수행합니다. Oracle은 기존 운영 절차를 따릅니다.

```sh
dnf update -y
dnf install -y chrony curl wget tar gzip unzip jq bind-utils nc procps-ng lsof
systemctl enable --now chronyd
timedatectl set-timezone Asia/Seoul
```

`inventory/hosts.example`을 `/etc/hosts`에 병합하거나 내부 DNS에 같은 레코드를 생성합니다. 파일 전체를 덮어쓰지 마십시오.

```sh
# 해당 VM에서 한 줄만 실행
hostnamectl set-hostname storage.labs.localhost.com   # VM1에서 실행
hostnamectl set-hostname compute.labs.localhost.com   # VM2에서 실행
getent hosts minio.labs.localhost.com polaris.labs.localhost.com doris-fe.labs.localhost.com
```

공통 운영 원칙:

- 서비스별 전용 OS 계정을 사용합니다.
- `/opt/<service>`는 바이너리, `/var/lib/<service>`는 데이터, `/var/log/<service>`는 로그로 구분합니다.
- Secret은 소유자 읽기 전용 환경 파일에 저장하고 Git에 커밋하지 않습니다.
- SELinux를 끄지 않습니다. 필요한 포트/파일 context를 명시적으로 허용합니다.
- NTP 오차를 확인합니다. OAuth2와 TLS는 시간이 어긋나면 실패합니다.
- `/tmp`나 사용자 홈을 영구 데이터 위치로 사용하지 않습니다.

설치 전 체크:

```sh
getenforce
timedatectl status
df -h
free -h
ulimit -n
```
