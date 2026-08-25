# Oracle 26ai: DG4ODBC와 ORACLE_BIGDATA

대상은 기존 Oracle Database 26ai host입니다. 이 POC의 기존 DB Home은 `DB_ORACLE_HOME=/home/oracle/app/db26`, 새 Gateway Home은 `GATEWAY_HOME=/home/oracle/app/gateway/26ai/dg4odbc`, PDB는 `ORCLPDB`, 애플리케이션 사용자는 `LAKE`입니다. Gateway listener는 같은 host의 `127.0.0.1:1522`, Doris DSN은 VM2 Public `129.153.132.242:9030`을 사용합니다.

## 1. Gateway와 ODBC 설치

Oracle Software Delivery Cloud에서 제품 검색/선택 시 **Oracle Database 26ai Gateways**를 선택하고, Linux x86-64용 설치 미디어를 내려받습니다. Oracle Universal Installer(OUI)에서 **Oracle Database Gateway for ODBC** 컴포넌트를 선택합니다.

운영 중인 DB Home에는 설치하지 않고 Gateway 전용 Home을 사용합니다. 이 방식은 기존 Database Home 변경 및 Gateway/DB 패치 간 간섭을 피합니다. Gateway, unixODBC, ODBC 드라이버는 모두 64-bit여야 합니다.

```bash
# oracle 사용자
export ORACLE_BASE=/home/oracle/app
export DB_ORACLE_HOME=/home/oracle/app/db26
export GATEWAY_HOME=/home/oracle/app/gateway/26ai/dg4odbc

mkdir -p /home/oracle/stage/dg4odbc-26ai
cd /home/oracle/stage/dg4odbc-26ai
unzip /다운로드경로/<Oracle-Database-26ai-Gateways-Linux-x86-64>.zip
./runInstaller
```

OUI에서 다음을 선택합니다.

- Oracle Base: `/home/oracle/app`
- Oracle Home: `/home/oracle/app/gateway/26ai/dg4odbc`
- Component: **Oracle Database Gateway for ODBC**

설치 마지막에 OUI가 출력하는 root 권한 스크립트만 별도 root 셸에서 실행합니다. 설치 프로그램이 제시하지 않은 `root.sh` 경로를 임의로 실행하지 마십시오.

```bash
ls -l /home/oracle/app/gateway/26ai/dg4odbc/bin/dg4odbc
```

```bash
sudo dnf install -y unixODBC
file /usr/lib64/libodbc.so.2
```

OL9 AppStream의 3.1.12에서 Gateway `SQLConnectW` 문자열이 손상됐던 검증 이력이 있으므로 이 POC 기준은 MariaDB Connector/ODBC 3.2.8입니다. Oracle Software Delivery Cloud가 아니라 [MariaDB Connector/ODBC 3.2.8 공식 파일 목록](https://dlm.mariadb.com/browse/odbc_connector/3.2.8/)에서 `mariadb-connector-odbc-3.2.8-1.el9.x86_64.rpm`을 받아 내부 저장소 또는 서버의 staging 경로에 둡니다. 기존 3.1.12를 그대로 사용하지 마십시오.

```bash
cd /home/oracle/stage
rpmkeys --checksig --verbose mariadb-connector-odbc-3.2.8-1.el9.x86_64.rpm
sudo dnf install -y ./mariadb-connector-odbc-3.2.8-1.el9.x86_64.rpm
rpm -q mariadb-connector-odbc
file /usr/lib64/libmaodbc.so
```

`rpmkeys --checksig --verbose`에서 header와 payload digest가 `OK`, signature가 `OK`여야 합니다. `NOKEY`는 파일 손상이 아니라 키 미등록 상태이므로 키 출처와 fingerprint 확인 후 `rpm --import`합니다.

## 2. unixODBC 수동 등록

기존 `/etc/odbcinst.ini`, `/etc/odbc.ini`를 백업한 뒤 각 템플릿의 section만 **추가**합니다. `odbcinst -i`로 덮어쓰지 않습니다.

- `config/oracle/odbcinst.ini` → `/etc/odbcinst.ini`
- `config/oracle/odbc.ini` → `/etc/odbc.ini`

DSN의 `PASSWORD=CHANGE_ME`를 Doris 계정 비밀번호로 바꾸고 권한을 제한합니다. 단, Gateway 프로세스는 `oracle` 사용자로 실행되므로 `/etc/odbc.ini`은 root만 읽는 `0600`으로 두면 안 됩니다. root가 소유하고 Oracle 소프트웨어 그룹에는 읽기 권한을 부여합니다. 이 POC에서는 `/etc/odbcinst.ini`에 다음 드라이버 section, `/etc/odbc.ini`에 `DorisProd` section을 추가합니다.

```ini
; /etc/odbcinst.ini
[MariaDB ODBC 3.2 Driver]
Description=64-bit MariaDB Connector/ODBC
Driver=/usr/lib64/libmaodbc.so
Threading=0
UsageCount=1
```

```ini
; /etc/odbc.ini
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

```bash
ORACLE_GROUP=$(id -gn)
sudo chown root:"${ORACLE_GROUP}" /etc/odbc.ini
sudo chmod 640 /etc/odbc.ini
odbcinst -j
odbcinst -q -d -n 'MariaDB ODBC 3.2 Driver'
odbcinst -q -s -n DorisProd
iusql -v DorisProd jsondoc_app '실제비밀번호'
```

`iusql` 연결이 먼저 성공해야 합니다. 종료 명령은 `quit`입니다.

## 3. Gateway 수동 구성

Oracle 소유자로 Gateway Home을 지정한 뒤 다음 템플릿을 직접 반영합니다. DB 접속 및 `sqlplus` 작업 시에는 기존 `DB_ORACLE_HOME=/home/oracle/app/db26`을 계속 사용합니다.

### DB Home과 Gateway Home을 섞지 않는 방법

두 Home의 역할을 다음처럼 고정합니다. Gateway listener의 `SID_DESC`에 있는 `ORACLE_HOME`과 `LD_LIBRARY_PATH`도 반드시 Gateway Home이어야 합니다. 이전 예제의 `/home/oracle/app/oracle/dbhome` 경로가 남아 있으면 `TNS-01201`로 `dg4odbc`를 찾지 못합니다.

| 작업 | 사용할 Home |
|---|---|
| `sqlplus`, PDB, DB link DDL | `DB_ORACLE_HOME=/home/oracle/app/db26` |
| `dg4odbc`, `initDORIS.ora`, `LISTENER_DORIS`, `tnsping DORIS_GATEWAY` | `GATEWAY_HOME=/home/oracle/app/gateway/26ai/dg4odbc` |

```bash
export DB_ORACLE_HOME=/home/oracle/app/db26
export GATEWAY_HOME=/home/oracle/app/gateway/26ai/dg4odbc
export ORACLE_HOME="$GATEWAY_HOME"
export TNS_ADMIN="$GATEWAY_HOME/network/admin"
export PATH="$ORACLE_HOME/bin:$PATH"
```

1. `config/oracle/initDORIS.ora` → `$GATEWAY_HOME/hs/admin/initDORIS.ora`
2. `config/oracle/listener-snippet.ora` → `$GATEWAY_HOME/network/admin/listener.ora`에 병합
3. `config/oracle/tnsnames-snippet.ora` → `$GATEWAY_HOME/network/admin/tnsnames.ora`와 `$DB_ORACLE_HOME/network/admin/tnsnames.ora` 모두에 병합

`GATEWAY_HOME`의 alias는 Gateway `tnsping`용이고, `DB_ORACLE_HOME`의 같은 alias는 Database server가 DB link를 해석할 때 필요합니다. 두 Home에서 하나의 공용 `TNS_ADMIN`을 사용하도록 이미 구성했다면 공용 `tnsnames.ora`에 한 번만 추가합니다.

`DorisProd`는 `/etc/odbc.ini`의 system DSN 이름이고 `DORIS`는 Gateway SID, `DORIS_GATEWAY`는 Oracle Net service 이름입니다.

```bash
export ORACLE_HOME=/home/oracle/app/gateway/26ai/dg4odbc
$ORACLE_HOME/bin/lsnrctl start LISTENER_DORIS
$ORACLE_HOME/bin/lsnrctl status LISTENER_DORIS
$ORACLE_HOME/bin/tnsping DORIS_GATEWAY
```

`HS_LANGUAGE=AMERICAN_AMERICA.WE8ISO8859P1`은 이 조합에서 필수로 검증된 호환 설정입니다. `AL32UTF8` 사용 시 MariaDB ODBC의 wide-character ABI와 충돌해 DSN/사용자명이 훼손되고 `ORA-28500`이 발생했습니다.

## 4. DB link와 metadata view

`config/oracle/01_doris_metadata.sql`의 비밀번호를 바꿔 `LAKE`로 실행합니다. SQL identifier는 대소문자 보존을 위해 큰따옴표를 유지합니다.

```sql
SELECT COUNT(*)
FROM "jsondoc_gateway"."file_metadata"@doris_link;
```

실패하면 `$ORACLE_HOME/hs/log/DORIS_agt_*.trc` 최신 파일과 unixODBC trace를 확인합니다. 진단이 끝나면 `HS_FDS_TRACE_LEVEL=OFF` 및 ODBC trace를 반드시 끕니다. trace에는 접속 정보가 남을 수 있습니다.

## 5. MinIO network ACL과 JSON 읽기

SYS로 `ORCLPDB`에 접속하여 `config/oracle/02_network_acl.sql`을 실행합니다. ACL 대상은 VM1 Public IP `141.148.12.16`, 포트는 9000입니다. IP literal에는 `resolve` privilege나 `private_target`이 필요하지 않습니다. 같은 ACE가 이미 있으면 중복 추가하지 말고 다음 조회로 먼저 확인합니다.

```sql
SELECT host, lower_port, upper_port, ace_order, principal, privilege
FROM dba_host_aces
WHERE principal = 'LAKE';
```

그 후 `LAKE`로 `JSONDOC_FILE_METADATA_V`에서 `object_uri`를 고르고 `config/oracle/03_bigdata_jsondoc.sql`의 URI를 교체해 실행합니다. 현재 POC는 MinIO bucket public-read 방식입니다. 운영에서는 HTTPS와 Oracle credential 기반 접근으로 바꾸십시오.

## 알려진 오류

- `ORA-28500`, trace의 SQLSTATE가 `I` 하나 및 메시지 `[` 하나: 3.1.12 wide-character 접속 문제 가능성이 높음. 3.2.8과 `HS_LANGUAGE` 확인.
- `ORA-24247`: `141.148.12.16`에 대한 `LAKE`의 `http`, `connect`와 9000 포트 범위 확인.
- DB link는 연결되지만 테이블이 안 보임: Doris external view는 `jsondoc_gateway.file_metadata`; Oracle에서는 `"jsondoc_gateway"."file_metadata"@doris_link` 사용.

공식 문서: [Oracle Database Gateway for ODBC 설치](https://docs.oracle.com/en/database/oracle/oracle-database/26/otgis/install-odbc-gateway.html), [DBMS_NETWORK_ACL_ADMIN](https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/DBMS_NETWORK_ACL_ADMIN.html).
