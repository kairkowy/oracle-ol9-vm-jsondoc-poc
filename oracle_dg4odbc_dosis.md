# Oracle 26ai DG4ODBC · Doris · Polaris · MinIO 단일 설치 가이드

이 문서는 Oracle Linux 9 VM 두 대와 기존 Oracle Database 26ai 서버에서 JSON 원본을 MinIO에 저장하고, Apache Polaris Iceberg catalog 및 Apache Doris를 거쳐 Oracle DB link로 조회하는 POC의 단일 설치 절차다. **Simba ODBC 드라이버는 사용하지 않는다.** Oracle Gateway는 무료 MariaDB Connector/ODBC 3.2.8과 unixODBC를 통해 Doris의 MySQL protocol(9030)에 연결한다.

## 1. 목표와 고정 주소

```text
Browser -> VM2 JSONDoc App -> VM1 MinIO (JSON 원본)
                              -> VM2 Doris -> VM1 Polaris -> VM1 MinIO (Iceberg)

Oracle 26ai -> DG4ODBC -> unixODBC -> MariaDB Connector/ODBC -> Doris FE:9030
Oracle 26ai -> ORACLE_BIGDATA/HTTP -> MinIO:9000
```

| 위치 | 역할 | Private IP | Public IP |
|---|---|---:|---:|
| VM1 `data-lake-vm` | PostgreSQL, MinIO, Polaris | `10.0.121.203` | `141.148.12.16` |
| VM2 `data-lake-app` | Doris FE/BE, JSONDoc App | `10.0.27.145` | `129.153.132.242` |
| Oracle DB host | Oracle 26ai, DG4ODBC | 기존 환경 | 기존 환경 |

VM1↔VM2 통신에는 Private IP를 사용한다. Oracle DB host에서 Doris는 `129.153.132.242:9030`, MinIO HTTP POC는 `141.148.12.16:9000`을 사용한다. OCI NSG/Security List와 firewalld는 필요한 source CIDR에만 아래 포트를 열어야 한다.

- VM1: VM2에서 `9000`, `8181`; 관리자에서 `9001`, `8182`; PostgreSQL `5432`는 localhost only
- VM2: Oracle DB host에서 `9030`; 사용자에서 `8501`; Doris 내부 포트는 Public 개방 금지

## 2. 공통 OL9 준비

VM1/VM2에서 `opc` 같은 sudo 권한 관리 계정으로 실행한다.

```bash
sudo dnf update -y
sudo dnf install -y chrony curl wget tar gzip unzip jq bind-utils nc procps-ng lsof
sudo systemctl enable --now chronyd
sudo timedatectl set-timezone Asia/Seoul
ip -4 -o addr show scope global
```

SELinux는 끄지 않는다. 서비스 파일·데이터 경로를 사용자 홈에서 `/opt`, `/var/lib`, `/etc`로 옮긴 경우에는 `restorecon`을 실행한다.

## 3. VM1: PostgreSQL 17

PostgreSQL은 Polaris catalog/RBAC의 영속 저장소이며 JSON이나 Iceberg 파일을 저장하지 않는다.

```bash
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo dnf -qy module disable postgresql
sudo dnf clean all
sudo dnf install -y postgresql17-server postgresql17
sudo /usr/pgsql-17/bin/postgresql-17-setup initdb
sudo systemctl enable --now postgresql-17
```

`/var/lib/pgsql/17/data/postgresql.conf`에 아래를 적용하고, `pg_hba.conf`에는 Polaris loopback만 허용한다.

```ini
listen_addresses = '127.0.0.1'
port = 5432
password_encryption = 'scram-sha-256'
```

```text
host    polaris    polaris    127.0.0.1/32    scram-sha-256
```

프로젝트의 `config/postgresql/10-polaris.sql`에서 비밀번호 placeholder를 실제 값으로 바꾼 후 실행한다.

```bash
cd /home/opc/labs/ol9-vm-poc
sudo -u postgres psql -v ON_ERROR_STOP=1 -f config/postgresql/10-polaris.sql
sudo systemctl restart postgresql-17
sudo ss -ltnp | grep 5432
```

## 4. VM1: MinIO

공식 MinIO RPM을 staging 경로에 내려받아 checksum/signature를 확인한 뒤 설치한다. MinIO RPM에 `mc`는 포함되지 않는다.

```bash
cd /home/opc/labs/ol9-vm-poc
sudo dnf install -y ./minio-20250723155402.0.0-1.x86_64.rpm
getent group minio >/dev/null || sudo groupadd --system minio
id minio >/dev/null 2>&1 || sudo useradd --system --gid minio \
  --home-dir /var/lib/minio --create-home --shell /sbin/nologin minio
sudo install -d -o minio -g minio -m 0750 /var/lib/minio/data
sudo install -o root -g minio -m 0640 config/minio/minio.env.example /etc/default/minio
sudo vi /etc/default/minio
```

`/etc/default/minio`에는 실제 `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, volume 및 options를 넣는다. MinIO는 `minio` 사용자로 이 파일을 읽으므로 `root:minio 0640`을 유지한다.

```bash
sudo install -d -m 0755 /etc/systemd/system/minio.service.d
sudo vi /etc/systemd/system/minio.service.d/override.conf
```

```ini
[Service]
User=minio
Group=minio
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now minio
sudo systemctl status minio --no-pager -l
curl -fsS -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1:9000/minio/health/live
```

`curl -fsS`가 아무 출력 없이 종료되고 exit code가 0이면 health check 성공이다. `217/USER`은 service 사용자 문제, `/etc/default/minio: permission denied`는 환경 파일의 group/read 권한 문제다.

`mc`를 설치하고 bucket을 준비한다.

```bash
curl -fLO https://dl.min.io/client/mc/release/linux-amd64/mc
sudo install -m 0755 mc /usr/local/bin/mc
mc alias set poc http://127.0.0.1:9000 minioadmin '<MINIO 실제 암호>'
mc mb --ignore-existing poc/jsondocs
mc cp sample/customer-001.json poc/jsondocs/samples/customer-001.json
mc stat poc/jsondocs/samples/customer-001.json
```

이 POC에서만 Oracle HTTP JSON 읽기용 public download를 허용한다.

```bash
mc anonymous set download poc/jsondocs
mc anonymous get poc/jsondocs
```

App/Oracle 같은 다른 호스트에서 `curl -f http://141.148.12.16:9000/jsondocs/samples/customer-001.json`으로 확인한다. MinIO VM 자신에서 Public IP를 호출하는 hairpin NAT 결과는 검증 근거로 사용하지 않는다.

## 5. VM1: Apache Polaris 1.7.0

```bash
sudo dnf install -y java-21-openjdk-headless
getent group polaris >/dev/null || sudo groupadd --system polaris
id polaris >/dev/null 2>&1 || sudo useradd --system --gid polaris \
  --home-dir /opt/polaris --shell /sbin/nologin polaris

cd /home/opc/labs/ol9-vm-poc
POLARIS_VERSION=1.7.0
curl -fLO https://downloads.apache.org/polaris/${POLARIS_VERSION}/polaris-bin-${POLARIS_VERSION}.tgz
curl -fLO https://downloads.apache.org/polaris/${POLARIS_VERSION}/polaris-bin-${POLARIS_VERSION}.tgz.sha512
expected=$(awk '{print $1}' polaris-bin-${POLARIS_VERSION}.tgz.sha512)
echo "${expected}  polaris-bin-${POLARIS_VERSION}.tgz" | sha512sum --check -
sudo tar -xzf polaris-bin-${POLARIS_VERSION}.tgz -C /opt
sudo ln -sfnT /opt/polaris-bin-${POLARIS_VERSION} /opt/polaris
sudo chown -R polaris:polaris /opt/polaris-bin-${POLARIS_VERSION}
sudo chmod 755 /opt/polaris-bin-${POLARIS_VERSION}/bin/admin /opt/polaris-bin-${POLARIS_VERSION}/bin/server
sudo restorecon -RFv /opt/polaris-bin-${POLARIS_VERSION}
sudo install -d -o root -g polaris -m 0750 /etc/polaris
sudo install -o root -g polaris -m 0640 config/polaris/polaris.env.example /etc/polaris/polaris.env
sudo vi /etc/polaris/polaris.env
```

`/home`에서 내려받은 archive를 `/opt`로 옮긴 뒤 SELinux label을 복구하지 않으면 `polaris.service`가 `203/EXEC Permission denied`로 실패한다.

최초 한 번 DB schema와 root principal을 bootstrap한다. `sudo -u`는 caller 환경을 전달하지 않으므로 `polaris.env`를 대상 사용자 셸에서 읽는다.

```bash
sudo -u polaris /bin/bash -c '
  set -a
  . /etc/polaris/polaris.env
  set +a
  exec /opt/polaris/bin/admin bootstrap \
    -r POLARIS \
    -c POLARIS,root,"<POLARIS_ROOT_CLIENT_SECRET>"
'

sudo install -m 0644 config/polaris/polaris.service /etc/systemd/system/polaris.service
sudo systemctl daemon-reload
sudo systemctl enable --now polaris
curl -fsS http://127.0.0.1:8182/q/health
sudo -u postgres psql -d polaris -c '\dt polaris_schema.*'
```

Polaris catalog는 VM1에서 `opc`로 생성한다. 외부 client(Doris)는 VM1 Private endpoint를, Polaris 자체는 loopback MinIO endpoint를 쓴다.

```bash
POLARIS_BASE_URL='http://127.0.0.1:8181' \
POLARIS_REALM='POLARIS' \
POLARIS_ROOT_CLIENT_ID='root' \
POLARIS_ROOT_CLIENT_SECRET='<POLARIS root 실제 암호>' \
POLARIS_CATALOG='jsondoc_catalog' \
MINIO_BUCKET='jsondocs' \
MINIO_ENDPOINT='http://10.0.121.203:9000' \
MINIO_ENDPOINT_INTERNAL='http://127.0.0.1:9000' \
python3 scripts/create-polaris-catalog.py
```

기대 출력은 `Created jsondoc_catalog: HTTP 201`이다. 이전에 잘못된 endpoint로 만든 빈 catalog가 있으면 OAuth token으로 DELETE한 뒤 위 명령으로 재생성한다.

## 6. VM2: Apache Doris 4.0.1

```bash
sudo dnf install -y java-17-openjdk-headless mariadb
sudo useradd --system --home-dir /opt/doris --shell /sbin/nologin doris

JAVA_BIN=$(readlink -f "$(command -v java)")
JAVA_HOME=$(dirname "$(dirname "$JAVA_BIN")")
test -x "$JAVA_HOME/bin/java" && echo 'Java: OK'

sudo vi /etc/sysctl.d/99-doris.conf
```

`99-doris.conf` 내용:

```ini
vm.max_map_count = 2000000
```

```bash
sudo sysctl --system
sysctl vm.max_map_count
swapon --show
sudo swapoff -a
```

재부팅 후 swap이 다시 올라오지 않도록 `/etc/fstab`의 활성 swap 행을 백업 후 주석 처리한다. Doris BE는 `vm.max_map_count` 부족, swap 활성화, 잘못된 Java home, 잘못된 `priority_networks` 중 하나가 있으면 시작하지 않는다.

```bash
cd /home/opc/labs/ol9-vm-poc
DORIS_VERSION=4.0.1
grep -m1 -o avx2 /proc/cpuinfo
curl -fLO https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-${DORIS_VERSION}-bin-x64.tar.gz
curl -fLO https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-${DORIS_VERSION}-bin-x64.tar.gz.sha512
expected=$(awk '{print $1}' apache-doris-${DORIS_VERSION}-bin-x64.tar.gz.sha512)
echo "${expected}  apache-doris-${DORIS_VERSION}-bin-x64.tar.gz" | sha512sum --check -
sudo tar -xzf apache-doris-${DORIS_VERSION}-bin-x64.tar.gz -C /opt
sudo ln -sfnT /opt/apache-doris-${DORIS_VERSION}-bin-x64 /opt/doris
sudo chown -R doris:doris /opt/apache-doris-${DORIS_VERSION}-bin-x64
sudo restorecon -RFv /opt/apache-doris-${DORIS_VERSION}-bin-x64
```

AVX2가 없으면 `bin-x64-noavx2` archive를 사용한다. `/opt/doris`는 archive directory가 아니라 symlink다.

```bash
sudo install -d -o doris -g doris -m 0750 /var/lib/doris/fe-meta /var/lib/doris/be-storage
sudo cp config/doris/fe.conf /opt/doris/fe/conf/fe.conf
sudo cp config/doris/be.conf /opt/doris/be/conf/be.conf
sudo sed -i "s|^JAVA_HOME = .*|JAVA_HOME = ${JAVA_HOME}|" /opt/doris/fe/conf/fe.conf /opt/doris/be/conf/be.conf
sudo sed -i 's|^priority_networks = .*|priority_networks = 10.0.27.145/32|' /opt/doris/fe/conf/fe.conf /opt/doris/be/conf/be.conf
sudo chown -R doris:doris /opt/doris/fe /opt/doris/be /var/lib/doris
sudo install -m 0644 config/doris/doris-fe.service config/doris/doris-be.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now doris-fe
mysqladmin -h127.0.0.1 -P9030 -uroot ping
sudo systemctl enable --now doris-be
```

BE가 `active (running)`인 것을 확인한 후 backend를 확인한다. 이전 잘못된 `10.0.121.203:9050` backend가 있으면 삭제한다.

```bash
mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM DROP BACKEND '10.0.121.203:9050'"
mysql -h127.0.0.1 -P9030 -uroot -e "ALTER SYSTEM ADD BACKEND '10.0.27.145:9050'"
mysql -h127.0.0.1 -P9030 -uroot -e 'SHOW BACKENDS\G'
```

`Alive: true`, `HeartbeatFailureCounter: 0`, `BePort: 9060`, `HttpPort: 8040`, `BrpcPort: 8060`을 확인한다. backend가 이미 있으면 ADD 오류를 무시하고 `SHOW BACKENDS` 결과로 판단한다.

Iceberg catalog, table, gateway view와 app user를 만든다.

```bash
sudo python3 -m venv /opt/jsondoc-admin-venv
sudo /opt/jsondoc-admin-venv/bin/pip install pymysql==1.1.2

DORIS_HOST='127.0.0.1' \
DORIS_APP_PASSWORD='<Doris jsondoc_app 실제 암호>' \
POLARIS_ROOT_CLIENT_SECRET='<POLARIS root 실제 암호>' \
MINIO_ROOT_USER='minioadmin' \
MINIO_ROOT_PASSWORD='<MinIO 실제 암호>' \
/opt/jsondoc-admin-venv/bin/python3 scripts/setup-doris.py
```

성공 메시지는 `Doris backend, catalog, Iceberg table, view, and app user are ready`다. `scripts/setup-doris.py` 안의 Polaris/MinIO endpoint는 모두 VM1 `10.0.121.203`이어야 한다. 이전 `10.0.27.145:8181`로 만들어진 `polaris_iceberg` catalog가 있으면 먼저 삭제하고 스크립트를 수정한 뒤 재실행한다.

```bash
mysql -h127.0.0.1 -P9030 -uroot -e 'DROP CATALOG IF EXISTS polaris_iceberg'
grep -nE 'iceberg\.rest\.uri|server-uri|s3\.endpoint' scripts/setup-doris.py
```

## 7. VM2: JSONDoc App

```bash
sudo dnf install -y python3.12
sudo useradd --system --home-dir /opt/jsondoc --shell /sbin/nologin jsondoc
sudo mkdir -p /opt/jsondoc/app/templates /etc/jsondoc
sudo cp app/main.py app/requirements.txt /opt/jsondoc/app/
sudo cp app/templates/index.html /opt/jsondoc/app/templates/
sudo python3.12 -m venv /opt/jsondoc/venv
sudo /opt/jsondoc/venv/bin/pip install --requirement /opt/jsondoc/app/requirements.txt
sudo cp config/app/jsondoc-app.env.example /etc/jsondoc/app.env
sudo cp config/app/jsondoc-app.service /etc/systemd/system/
sudo chown -R jsondoc:jsondoc /opt/jsondoc
sudo chmod 600 /etc/jsondoc/app.env
sudo vi /etc/jsondoc/app.env
```

다음 주소는 고정하고 두 password만 실제 값으로 바꾼다.

```ini
MINIO_ENDPOINT=10.0.121.203:9000
MINIO_PUBLIC_ENDPOINT=141.148.12.16:9000
MINIO_BUCKET=jsondocs
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=CHANGE_ME
DORIS_HOST=127.0.0.1
DORIS_USER=jsondoc_app
DORIS_PASSWORD=CHANGE_ME
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now jsondoc-app
curl -fsS http://127.0.0.1:8501/health
```

브라우저에서 `http://129.153.132.242:8501`을 열어 JSON을 업로드한다. `Internal Server Error`와 log의 `host='10.0.27.145', port=9000`는 앱 환경 파일의 `MINIO_ENDPOINT`가 VM2 자신으로 잘못 설정된 경우다. `10.0.121.203:9000`으로 수정하고 `sudo systemctl restart jsondoc-app`을 실행한다.

## 8. Oracle 26ai: 무료 ODBC와 DG4ODBC

이 절은 기존 Oracle DB Home과 별도 Gateway Home을 사용한다.

```text
DB_ORACLE_HOME=/home/oracle/app/db26
GATEWAY_HOME=/home/oracle/app/gateway/26ai/dg4odbc
PDB=ORCLPDB
```

Oracle Software Delivery Cloud에서 **Oracle Database 26ai Gateways**를 선택하고 Linux x86-64 설치 media를 받는다. OUI에서 **Oracle Database Gateway for ODBC**를 선택하고 Oracle Home을 `GATEWAY_HOME`으로 지정한다. OUI가 표시한 root script만 실행한다.

```bash
# oracle 사용자
export ORACLE_BASE=/home/oracle/app
export DB_ORACLE_HOME=/home/oracle/app/db26
export GATEWAY_HOME=/home/oracle/app/gateway/26ai/dg4odbc
ls -l "$GATEWAY_HOME/bin/dg4odbc"

sudo dnf install -y unixODBC
```

OL9 기본 MariaDB Connector/ODBC 3.1.12는 사용하지 않는다. [MariaDB 공식 3.2.8 파일 목록](https://dlm.mariadb.com/browse/odbc_connector/3.2.8/)에서 `mariadb-connector-odbc-3.2.8-1.el9.x86_64.rpm`을 내려받아 검증 후 설치한다.

```bash
cd /home/oracle/stage
rpmkeys --checksig --verbose mariadb-connector-odbc-3.2.8-1.el9.x86_64.rpm
sudo dnf install -y ./mariadb-connector-odbc-3.2.8-1.el9.x86_64.rpm
rpm -q mariadb-connector-odbc
file /usr/lib64/libodbc.so.2 /usr/lib64/libmaodbc.so
```

`/etc/odbcinst.ini`에 다음 section을 추가한다.

```ini
[MariaDB ODBC 3.2 Driver]
Description=64-bit MariaDB Connector/ODBC
Driver=/usr/lib64/libmaodbc.so
Threading=0
UsageCount=1
```

`/etc/odbc.ini`에 DSN을 추가한다.

```ini
[DorisProd]
Description=Apache Doris JSONDoc Lakehouse
Driver=MariaDB ODBC 3.2 Driver
SERVER=129.153.132.242
PORT=9030
USER=jsondoc_app
PASSWORD=CHANGE_ME
DATABASE=jsondoc_gateway
CHARSET=utf8mb4
```

Gateway process가 `oracle` 사용자로 DSN을 읽어야 하므로 root-only `0600`은 사용하지 않는다.

```bash
ORACLE_GROUP=$(id -gn)
sudo chown root:"${ORACLE_GROUP}" /etc/odbc.ini
sudo chmod 640 /etc/odbc.ini
odbcinst -q -d -n 'MariaDB ODBC 3.2 Driver'
odbcinst -q -s -n DorisProd
iusql -v DorisProd jsondoc_app '<Doris jsondoc_app 실제 암호>'
```

`Connected!`가 나온 뒤에만 Gateway를 구성한다.

`config/oracle/initDORIS.ora`를 `$GATEWAY_HOME/hs/admin/initDORIS.ora`로 반영한다. `HS_FDS_CONNECT_INFO=DorisProd`, `HS_FDS_SHAREABLE_NAME=/usr/lib64/libodbc.so.2`, `HS_LANGUAGE=AMERICAN_AMERICA.WE8ISO8859P1` 및 `LD_LIBRARY_PATH`의 Gateway Home 경로를 유지한다.

`config/oracle/listener-snippet.ora`는 `$GATEWAY_HOME/network/admin/listener.ora`에 **병합**한다. `SID_NAME=DORIS` section의 `ORACLE_HOME`과 `LD_LIBRARY_PATH`는 모두 `/home/oracle/app/gateway/26ai/dg4odbc`여야 한다.

`config/oracle/tnsnames-snippet.ora`는 다음 두 파일에 모두 병합한다.

```text
/home/oracle/app/gateway/26ai/dg4odbc/network/admin/tnsnames.ora
/home/oracle/app/db26/network/admin/tnsnames.ora
```

평소 SQL*Plus/DB link 작업은 DB Home을 유지한다. Gateway listener 제어에만 일회성 환경을 사용한다.

```bash
# 평소 DB 작업 환경
export ORACLE_HOME=/home/oracle/app/db26
export TNS_ADMIN=$ORACLE_HOME/network/admin
export PATH=$ORACLE_HOME/bin:$PATH

# Gateway listener 제어
env \
  ORACLE_HOME=/home/oracle/app/gateway/26ai/dg4odbc \
  TNS_ADMIN=/home/oracle/app/gateway/26ai/dg4odbc/network/admin \
  PATH=/home/oracle/app/gateway/26ai/dg4odbc/bin:$PATH \
  /home/oracle/app/gateway/26ai/dg4odbc/bin/lsnrctl start LISTENER_DORIS
```

Gateway 확인:

```bash
env \
  ORACLE_HOME=/home/oracle/app/gateway/26ai/dg4odbc \
  TNS_ADMIN=/home/oracle/app/gateway/26ai/dg4odbc/network/admin \
  PATH=/home/oracle/app/gateway/26ai/dg4odbc/bin:$PATH \
  /home/oracle/app/gateway/26ai/dg4odbc/bin/lsnrctl status LISTENER_DORIS
```

DB listener(1521)와 Gateway listener(1522)는 독립적이다. `sqlplus ...@orclpdb`가 `ORA-12514`면 SYSDBA에서 PDB open 상태와 `LOCAL_LISTENER`를 확인하고 `ALTER SYSTEM REGISTER`를 실행한다.

`LAKE`로 PDB에 접속해 프로젝트의 `config/oracle/01_doris_metadata.sql`에서 password placeholder를 바꾼 뒤 실행한다. 또는 다음처럼 DB link를 만든다.

```sql
CREATE DATABASE LINK doris_link
CONNECT TO "jsondoc_app" IDENTIFIED BY "CHANGE_ME"
USING 'DORIS_GATEWAY';

SELECT COUNT(*)
FROM "jsondoc_gateway"."file_metadata"@doris_link;
```

## 9. 최종 검증

VM1:

```bash
sudo systemctl status postgresql-17 minio polaris --no-pager
curl -fsS http://127.0.0.1:9000/minio/health/live
curl -fsS http://127.0.0.1:8182/q/health
```

VM2:

```bash
sudo systemctl status doris-fe doris-be jsondoc-app --no-pager
mysql -h127.0.0.1 -P9030 -uroot -e 'SHOW BACKENDS\G'
mysql -h127.0.0.1 -P9030 -uroot -e 'SHOW CATALOGS; SHOW TABLES FROM polaris_iceberg.jsondoc;'
mysql -h127.0.0.1 -P9030 -uroot -e 'SELECT COUNT(*) AS metadata_rows FROM jsondoc_gateway.file_metadata'
```

브라우저에서 `customer-001.json`을 올린 뒤 Oracle에서 확인한다.

```sql
SELECT document_id, document_type, file_name, byte_size, object_uri
FROM "jsondoc_gateway"."file_metadata"@doris_link;
```

`customer-001` 행이 조회되면 다음 전체 경로가 성공한 것이다.

```text
Oracle 26ai -> DG4ODBC -> unixODBC -> MariaDB Connector/ODBC -> Doris
             -> Polaris REST catalog -> Iceberg -> MinIO JSON/object metadata
```

## 10. 자주 발생한 오류

| 증상 | 원인과 조치 |
|---|---|
| MinIO `217/USER` | systemd drop-in에 `User=minio`, `Group=minio`를 설정한다. |
| MinIO env permission denied | `/etc/default/minio`을 `root:minio`, `0640`으로 설정한다. |
| Polaris `203/EXEC` | `/opt/polaris-bin-*`에 `sudo restorecon -RFv`를 실행한다. |
| Doris BE map count 오류 | `vm.max_map_count=2000000` 적용 후 `sudo sysctl --system` 실행. |
| Doris BE Java 오류 | 실제 `JAVA_HOME`을 계산해 FE/BE config에 반영한다. |
| Doris BE가 VM1 IP로 advertise | `priority_networks = 10.0.27.145/32`로 수정하고 old backend를 제거한다. |
| App upload 500, `10.0.27.145:9000` | `/etc/jsondoc/app.env`의 `MINIO_ENDPOINT=10.0.121.203:9000`으로 수정 후 app 재시작. |
| `odbcinst`가 DSN을 못 읽음 | `/etc/odbc.ini`을 `root:<oracle-group>`, `0640`으로 설정한다. |
| Gateway `TNS-01201` | listener의 DORIS SID가 DB Home이 아닌 Gateway Home을 가리키게 수정한다. |
| DB link `ORA-12154` | `DORIS_GATEWAY` alias를 DB Home `tnsnames.ora`에도 추가한다. |
| `sqlplus ...@orclpdb` `ORA-12514` | DB listener의 서비스 등록 문제다. PDB open, `LOCAL_LISTENER`, `ALTER SYSTEM REGISTER`를 확인한다. |

POC 종료 후에는 bucket public-read를 제거하고, 모든 placeholder password와 POC용 `admin123`을 교체하며, TLS와 source-IP ACL을 적용한다.
