# Oracle Database Gateway for ODBC와 Trino 연결

이 문서는 Oracle AI Database 26ai 서버와 같은 호스트에 Oracle Database Gateway for ODBC(`dg4odbc`)를 설치하고 Trino에 연결하는 절차입니다.

## 1. 구성과 설치 순서

```text
Oracle Database 26ai
  → Oracle Net / database link
  → Oracle Database Gateway for ODBC (dg4odbc)
  → unixODBC Driver Manager
  → 64-bit vendor Trino ODBC driver
  → Trino :8080
```

반드시 다음 순서로 진행합니다.

1. Oracle Database Gateway for ODBC 제품 설치
2. unixODBC와 64-bit Trino ODBC vendor driver 설치
3. `/etc/odbc.ini` DSN 구성 및 `isql` 검증
4. `initTRINO.ora`, listener, TNS 구성
5. Oracle database link와 원격 조회 검증

## 2. 설치 전 확인

Oracle 소프트웨어 소유자 계정과 목표 Oracle home은 다음을 사용합니다.

```sh
id oracle
export ORACLE_HOME=/home/oracle/app/oracle/dbhome
export PATH="$ORACLE_HOME/bin:$PATH"
getconf LONG_BIT
```

`getconf LONG_BIT`는 `64`여야 합니다. 기존 Database와 같은 Oracle home에 Gateway를 설치하려면 Database와 Gateway가 모두 26ai로 동일한 release여야 합니다. 서로 다른 release를 같은 Oracle home에 설치하면 안 됩니다. Oracle Universal Installer가 기존 home 사용을 거부하거나 release가 다르면 별도 26ai Gateway home을 사용하고 본 프로젝트의 `ORACLE_HOME` 경로를 함께 변경해야 합니다.

설치 여부를 확인합니다.

```sh
test -x "$ORACLE_HOME/bin/dg4odbc" \
  && "$ORACLE_HOME/bin/dg4odbc" 2>&1 | head \
  || echo "Oracle Database Gateway for ODBC is not installed"
```

`$ORACLE_HOME/hs/admin/initdg4odbc.ora` 파일만 존재하는 것은 Gateway 제품 설치 확인으로 충분하지 않습니다. 반드시 `$ORACLE_HOME/bin/dg4odbc` 실행 파일이 있어야 합니다.

## 3. Oracle Database Gateway for ODBC 설치

Oracle Software Downloads에서 **Oracle Database Gateways 26ai for Linux x86-64** 설치 미디어를 내려받습니다. Oracle Database 설치 미디어가 아니라 Database Gateways 설치 미디어가 필요합니다. 배포 전에 Oracle Support의 certification matrix에서 현재 Oracle Linux 9 버전과 Gateway 26ai 조합을 확인합니다.

다운로드한 설치 파일을 Oracle 계정이 읽을 수 있는 임시 디렉터리에 압축 해제합니다. 실제 파일명은 받은 배포 파일에 맞춥니다.

```sh
su - oracle
mkdir -p /home/oracle/stage/gateway26ai
cd /home/oracle/stage/gateway26ai
unzip /설치파일경로/<oracle-database-gateways-26ai-linux-x86-64>.zip
```

GUI 설치가 가능한 경우 Oracle 계정으로 Oracle Universal Installer를 실행합니다.

```sh
export DISPLAY=<X-server>:0.0
cd /home/oracle/stage/gateway26ai
./runInstaller
```

OUI 화면에서 다음을 선택합니다.

1. Oracle Home: `/home/oracle/app/oracle/dbhome`
2. Available Product Components: **Oracle Database Gateway for ODBC 26ai**
3. Prerequisite Check 오류 확인 및 해결
4. Summary에서 `Oracle Database Gateway for ODBC` 선택 여부 확인
5. Install 실행
6. OUI가 root script 실행을 요청하면 별도 root 터미널에서 표시된 정확한 스크립트를 실행
7. 기존 Database listener 구성을 자동 변경하지 않고 설치 완료

X Window가 없는 서버에서는 설치 미디어에 포함된 response file을 복사하여 사용합니다. Response file의 정확한 이름과 product component key는 배포 미디어마다 확인하고, 미디어의 sample response file을 수정해야 합니다. 임의의 component key를 작성하지 마십시오.

```sh
find /home/oracle/stage/gateway26ai -type f -path '*/response/*' -maxdepth 5
./runInstaller -silent -responseFile /절대경로/수정한-response-file.rsp
```

설치 직후 다음 파일을 확인합니다.

```sh
export ORACLE_HOME=/home/oracle/app/oracle/dbhome
ls -l "$ORACLE_HOME/bin/dg4odbc"
ls -l "$ORACLE_HOME/hs/admin/initdg4odbc.ora"
ldd "$ORACLE_HOME/bin/dg4odbc" | grep 'not found' || true
```

`dg4odbc`가 없거나 `ldd`에 `not found`가 나오면 이후 구성을 진행하지 말고 OUI 설치 로그와 prerequisite 결과를 먼저 확인합니다.

## 4. unixODBC와 Trino ODBC driver 설치

root 계정에서 unixODBC runtime을 설치합니다.

```sh
dnf install -y unixODBC
ls -l /usr/lib64/libodbc.so.2
odbcinst -j
```

unixODBC는 Driver Manager이며 Trino driver를 포함하지 않습니다. Simba/insightsoftware Trino ODBC 또는 Starburst V2 Linux ODBC 등 Community Trino 483과 호환되는 64-bit Oracle Linux/RHEL driver RPM을 별도로 준비합니다.

```sh
dnf install -y ./<vendor-trino-odbc-driver>.x86_64.rpm
rpm -qa | grep -Ei 'trino|starburst|simba|odbc'
rpm -ql <설치된-driver-package> | grep '\.so'
```

실제 driver library와 의존성을 확인합니다.

```sh
DRIVER_SO=/실제/vendor/driver/lib/driver64.so
test -f "$DRIVER_SO"
file "$DRIVER_SO"
ldd "$DRIVER_SO"
```

driver와 `dg4odbc`는 모두 64-bit여야 하고 `ldd` 결과에 `not found`가 없어야 합니다.

## 5. Trino DSN 구성과 직접 검증

프로젝트의 `oracle/gateway/odbcinst.ini`에서 Simba driver `.so` 경로를 실제 값으로 변경하여 `/etc/odbcinst.ini`에 등록합니다. 이 파일은 unixODBC에 **driver 이름과 실제 공유 라이브러리 위치**를 알려줍니다.

### `oracle/gateway/odbcinst.ini` 전체 내용

```ini
[Simba Trino ODBC Driver]
Description=64-bit Simba Trino ODBC Driver
Driver=/실제/simba/trino/lib/driver64.so
Setup=/실제/simba/trino/lib/driver64.so
UsageCount=1
```

`Driver`와 `Setup`의 예시 경로는 placeholder입니다. RPM 설치 후 다음 명령으로 확인한 실제 64-bit `.so` 절대 경로를 입력합니다.

```sh
rpm -ql <설치된-Simba-패키지명> | grep '\.so'
file /실제/simba/trino/lib/driver64.so
ldd /실제/simba/trino/lib/driver64.so
```

`file` 출력은 64-bit ELF여야 하며 `ldd` 출력에는 `not found`가 없어야 합니다.

`oracle/gateway/odbc.ini`는 `TrinoProd` system DSN으로 `/etc/odbc.ini`에 설치합니다. `Driver` 값은 위 `odbcinst.ini`의 section 이름과 정확히 일치해야 합니다.

### `oracle/gateway/odbc.ini` 전체 내용

```ini
[TrinoProd]
Description=Trino JSONDoc Lakehouse
Driver=Simba Trino ODBC Driver
Host=woko.labs.localhost.com
Port=8080
Catalog=iceberg
Schema=jsondoc
SSL=0
AuthenticationType=No Authentication
```

각 항목의 의미는 다음과 같습니다.

- `[TrinoProd]`: `HS_FDS_CONNECT_INFO=TrinoProd`와 `isql -v TrinoProd`에서 사용하는 system DSN 이름
- `Driver`: `/etc/odbcinst.ini`의 `[Simba Trino ODBC Driver]` section 이름과 정확히 일치
- `Host`: Trino coordinator에 접근 가능한 hostname 또는 IP
- `Port`: Trino HTTP port, 현재 Compose 구성은 `8080`
- `Catalog`: Trino Iceberg catalog 이름
- `Schema`: 기본 Iceberg namespace
- `SSL`: 현재 HTTP 테스트 환경은 `0`; HTTPS 운영 환경에서는 vendor 문서에 따라 변경
- `AuthenticationType`: 현재 Trino는 인증을 사용하지 않음; 실제 keyword는 설치한 Simba driver 버전 문서를 우선

등록 전에 두 템플릿 파일을 확인합니다.

```sh
grep -n . oracle/gateway/odbcinst.ini
grep -n . oracle/gateway/odbc.ini
grep -R '/absolute/path/to' oracle/gateway/odbcinst.ini oracle/gateway/odbc.ini \
  && echo 'ERROR: 실제 Simba driver 경로로 변경 필요' \
  || echo 'OK: placeholder 없음'
```

기존 `/etc/odbcinst.ini`를 덮어쓰지 말고 unixODBC 등록 명령으로 driver와 system DSN을 병합합니다. 프로젝트 루트에서 root로 실행합니다.

```sh
odbcinst -i -d -f oracle/gateway/odbcinst.ini
odbcinst -i -s -l -f oracle/gateway/odbc.ini
odbcinst -q -d -n 'Simba Trino ODBC Driver'
odbcinst -q -s -n TrinoProd
```

등록 후 실제 system 설정을 확인합니다.

```sh
cat /etc/odbcinst.ini
cat /etc/odbc.ini
odbcinst -q -d -n 'Simba Trino ODBC Driver'
odbcinst -q -s -n TrinoProd
```

정상 출력에는 최소한 다음 값이 있어야 합니다.

```text
[Simba Trino ODBC Driver]
Driver=/실제/simba/trino/lib/driver64.so

[TrinoProd]
Driver=Simba Trino ODBC Driver
Host=woko.labs.localhost.com
Port=8080
```

DSN keyword는 vendor마다 다를 수 있으므로 설치한 driver 문서의 Linux connection properties를 우선합니다. 특히 `AuthenticationType`, `UID`, `PWD`, `SSL` 이름은 공급사별로 다를 수 있습니다.

Oracle 계정으로 Oracle을 거치지 않고 ODBC를 먼저 검증합니다.

```sh
su - oracle
export ORACLE_HOME=/home/oracle/app/oracle/dbhome
export ODBCINI=/etc/odbc.ini
export LD_LIBRARY_PATH=/usr/lib64:/실제/vendor/driver/lib:$ORACLE_HOME/lib

odbcinst -q -d
odbcinst -q -d -n 'Simba Trino ODBC Driver'
odbcinst -q -s
isql -v TrinoProd jsondoc_app unused-no-auth
```

`isql`에서 다음 SQL이 성공해야 합니다.

```sql
SELECT count(*) FROM iceberg.jsondoc.file_metadata;
```

`isql`이 실패하면 database link로 진행하지 않습니다. `/etc/odbc.ini`, driver keyword, `.so` 경로 및 `ldd` 결과를 먼저 수정합니다.

## 6. Gateway와 Oracle Net 구성

프로젝트 루트에서 Oracle 계정으로 적용 스크립트를 실행합니다.

```sh
sh scripts/apply-oracle-gateway-config.sh
```

적용 결과는 다음과 같습니다.

- `/home/oracle/app/oracle/dbhome/hs/admin/initTRINO.ora`
- `/home/oracle/app/oracle/dbhome/network/admin/listener.ora`의 `LISTENER_TRINO:1522`
- `/home/oracle/app/oracle/dbhome/network/admin/tnsnames.ora`의 `TRINO_GATEWAY`

`listener-snippet.ora`의 `LD_LIBRARY_PATH` placeholder를 실제 vendor driver 디렉터리로 바꾼 후 적용해야 합니다. 설정을 확인하고 listener를 시작합니다.

이 프로젝트가 사용하는 OL9 Gateway 호스트에서는 `HS_LANGUAGE=AMERICAN_AMERICA.AL32UTF8` 설정 시 DG4ODBC가 `SQLConnectW`로 전달한 DSN과 사용자명이 훼손되어 unixODBC가 `IM002`를 반환하고 Oracle에는 `ORA-28500`이 표시됐습니다. 검증된 설정은 다음과 같습니다.

```ini
HS_LANGUAGE=AMERICAN_AMERICA.WE8ISO8859P1
```

프로젝트의 `oracle/gateway/initTRINO.ora`에도 이 값을 사용합니다. 변경 후에는 기존 Gateway 세션을 닫고 `LISTENER_TRINO`를 완전히 재시작해야 합니다.

```sh
grep -n . "$ORACLE_HOME/hs/admin/initTRINO.ora"
lsnrctl start LISTENER_TRINO
lsnrctl status LISTENER_TRINO
tnsping TRINO_GATEWAY
```

listener 상태에 `Service "TRINO"`, instance status `UNKNOWN`, program `dg4odbc`가 나타나는 것은 정적 Gateway SID의 정상적인 표시입니다.

## 7. Database link와 Trino 조회

Oracle Database에서 database link를 생성합니다. 현재 Trino는 인증을 사용하지 않으므로 비밀번호는 ODBC 구문을 위한 dummy 값입니다.

```sql
CREATE DATABASE LINK trino_link
  CONNECT TO "jsondoc_app" IDENTIFIED BY "unused-no-auth"
  USING 'TRINO_GATEWAY';
```

Oracle remote object 문법은 `schema.table@dblink`까지만 허용합니다. Trino catalog `iceberg`는 DSN에서 선택합니다.

```sql
SELECT COUNT(*)
FROM "jsondoc"."file_metadata"@trino_link;
```

성공한 뒤 `oracle/sql/01_trino_metadata_view.sql`을 실행합니다.

## 8. 장애 진단 순서

```text
1. dg4odbc 실행 파일 존재
2. vendor driver .so 존재 및 ldd 성공
3. isql DSN 연결 성공
4. LISTENER_TRINO와 tnsping 성공
5. database link COUNT(*) 성공
6. metadata view 생성
```

Gateway 상세 진단이 필요할 때만 `initTRINO.ora`에 다음을 임시 설정합니다.

```ini
HS_FDS_TRACE_LEVEL=DEBUG
```

재시험 전에 기존 Gateway 세션을 닫습니다.

```sql
ALTER SESSION CLOSE DATABASE LINK trino_link;
```

진단 완료 후 trace level을 `OFF`로 되돌립니다.

### `isql`은 성공하지만 Oracle에서 `ORA-28500`이 발생하는 경우

unixODBC trace를 활성화하여 `isql`과 DG4ODBC의 연결 호출을 비교합니다. `isql`의 `SQLConnect`는 정상 DSN으로 성공하지만 DG4ODBC의 `SQLConnectW`에서 `Server Name`이나 `User Name`이 중간 문자만 남는 형태로 훼손되고 `IM002`가 발생하면 인증이나 원격 서버 문제가 아니라 wide-character ABI 문제입니다.

```text
SQLConnectW
Server Name = [훼손된 DSN]
Error: IM002
Data source name not found and no default driver specified
```

이 경우 `initTRINO.ora`에서 다음 값을 사용하고 listener를 재시작합니다.

```ini
HS_LANGUAGE=AMERICAN_AMERICA.WE8ISO8859P1
```

`WE8ISO8859P1`은 한글을 표현하지 못하므로 이 랩에서는 영문 객체명과 영문 메타정보에 사용합니다. 한글 파일명이나 한글 메타데이터를 Oracle로 전달하려면 Oracle DG4ODBC와 SQLWCHAR ABI가 일치하는 unixODBC/vendor driver 조합을 별도로 검증해야 합니다. 진단이 끝나면 Gateway와 unixODBC trace를 모두 끕니다.
