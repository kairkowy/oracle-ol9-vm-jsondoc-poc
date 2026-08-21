# Oracle 26ai: DG4ODBC와 ORACLE_BIGDATA

대상: 기존 Oracle Database 26ai가 있는 `oracle.labs.localhost.com`. 예시는 `ORACLE_HOME=/home/oracle/app/oracle/dbhome`, PDB `ORCLPDB`, 애플리케이션 사용자 `LAKE`입니다.

## 1. Gateway와 ODBC 설치

Oracle Universal Installer로 **Oracle Database Gateway for ODBC 26ai x86-64**를 설치합니다. DB와 같은 Oracle Home을 사용한다면 기존 소프트웨어를 덮어쓰지 말고 Gateway 제품만 추가합니다. Gateway, unixODBC, ODBC 드라이버는 모두 64-bit여야 합니다.

```bash
sudo dnf install -y unixODBC mariadb-connector-odbc
file /usr/lib64/libodbc.so.2 /usr/lib64/libmaodbc.so
```

OL9 AppStream의 3.1.12에서 Gateway `SQLConnectW` 문자열이 손상됐던 검증 이력이 있으므로 이 POC 기준은 MariaDB Connector/ODBC 3.2.8입니다. 공식 RPM과 공개키를 검증하고 내부 저장소를 통해 설치하십시오. `rpmkeys --checksig --verbose package.rpm`에서 header와 payload digest가 `OK`, signature가 `OK`여야 합니다. `NOKEY`는 파일 손상이 아니라 키 미등록 상태이므로 키 출처와 fingerprint 확인 후 `rpm --import`합니다.

## 2. unixODBC 수동 등록

기존 `/etc/odbcinst.ini`, `/etc/odbc.ini`를 백업한 뒤 각 템플릿의 section만 **추가**합니다. `odbcinst -i`로 덮어쓰지 않습니다.

- `config/oracle/odbcinst.ini` → `/etc/odbcinst.ini`
- `config/oracle/odbc.ini` → `/etc/odbc.ini`

DSN의 `PASSWORD=CHANGE_ME`를 Doris 계정 비밀번호로 바꾸고 권한을 제한합니다.

```bash
sudo chmod 600 /etc/odbc.ini
odbcinst -j
odbcinst -q -d -n 'MariaDB ODBC 3.2 Driver'
odbcinst -q -s -n DorisProd
iusql -v DorisProd jsondoc_app '실제비밀번호'
```

`iusql` 연결이 먼저 성공해야 합니다. 종료 명령은 `quit`입니다.

## 3. Gateway 수동 구성

Oracle 소유자로 다음 템플릿을 직접 반영합니다.

1. `config/oracle/initDORIS.ora` → `$ORACLE_HOME/hs/admin/initDORIS.ora`
2. `config/oracle/listener-snippet.ora` → `$ORACLE_HOME/network/admin/listener.ora`에 병합
3. `config/oracle/tnsnames-snippet.ora` → `$ORACLE_HOME/network/admin/tnsnames.ora`에 병합

`DorisProd`는 `/etc/odbc.ini`의 system DSN 이름이고 `DORIS`는 Gateway SID, `DORIS_GATEWAY`는 Oracle Net service 이름입니다.

```bash
export ORACLE_HOME=/home/oracle/app/oracle/dbhome
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

SYS로 `ORCLPDB`에 접속하여 `config/oracle/02_network_acl.sql`을 실행합니다. 같은 ACE가 이미 있으면 중복 추가하지 말고 다음 조회로 먼저 확인합니다.

```sql
SELECT host, lower_port, upper_port, ace_order, principal, privilege
FROM dba_host_aces
WHERE principal = 'LAKE';
```

그 후 `LAKE`로 `JSONDOC_FILE_METADATA_V`에서 `object_uri`를 고르고 `config/oracle/03_bigdata_jsondoc.sql`의 URI를 교체해 실행합니다. 현재 POC는 MinIO bucket public-read 방식입니다. 운영에서는 HTTPS와 Oracle credential 기반 접근으로 바꾸십시오.

## 알려진 오류

- `ORA-28500`, trace의 SQLSTATE가 `I` 하나 및 메시지 `[` 하나: 3.1.12 wide-character 접속 문제 가능성이 높음. 3.2.8과 `HS_LANGUAGE` 확인.
- `ORA-24266 expected private got public`: private 주소를 해석하는 ACL에 `private_target => TRUE` 누락.
- `ORA-24247`: `LAKE`의 `resolve`, `http`, `connect`와 9000 포트 범위 확인.
- DB link는 연결되지만 테이블이 안 보임: Doris external view는 `jsondoc_gateway.file_metadata`; Oracle에서는 `"jsondoc_gateway"."file_metadata"@doris_link` 사용.

공식 문서: [Oracle Database Gateway for ODBC 설치](https://docs.oracle.com/en/database/oracle/oracle-database/26/otgis/install-odbc-gateway.html), [DBMS_NETWORK_ACL_ADMIN](https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/DBMS_NETWORK_ACL_ADMIN.html).
