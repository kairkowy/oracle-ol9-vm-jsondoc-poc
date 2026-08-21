# Oracle 26ai · DG4ODBC · Trino · Iceberg JSONDoc Lab

JSON 원본은 MinIO에, 검색용 파일 메타정보는 Iceberg/Parquet에 저장합니다. Apache Polaris가 Iceberg REST Catalog를 제공하고 PostgreSQL에 Polaris의 카탈로그 상태를 영속 저장합니다. Oracle AI Database 26ai는 Database Gateway for ODBC를 통해 Trino의 메타정보를 검색하고, 검색된 `object_uri`를 `ORACLE_BIGDATA`의 `jsondoc` 외부 테이블로 직접 읽습니다. Oracle Database 자체는 Compose에 포함하지 않습니다.

## 구성

- `http://192.168.56.10:8501` — JSON 업로드/메타정보 화면
- `http://192.168.56.10:9001` — MinIO Console
- `http://192.168.56.10:8080` — Trino
- `http://192.168.56.10:8181` — Apache Polaris Iceberg REST/Management API
- `192.168.56.10:5432` — Polaris 전용 PostgreSQL
- MinIO bucket `jsondocs`: 원본 JSON과 Iceberg warehouse
- Polaris catalog `jsondoc_catalog`: Iceberg namespace/table 등록과 현재 metadata pointer
- PostgreSQL database `polaris`: Polaris 내부 catalog/RBAC 상태
- Iceberg table `iceberg.jsondoc.file_metadata`: 파일명, 크기, SHA-256, URI, 문서 ID/종류

### PostgreSQL 사용 용도

PostgreSQL은 업무 데이터나 JSON 문서를 저장하는 데이터베이스가 아니라, Polaris 서비스 전용 영속 저장소입니다. Polaris 컨테이너가 재시작되거나 재생성되어도 다음 정보를 유지하는 데 사용합니다.

- Polaris realm과 catalog 등록정보
- namespace, table, view 등록정보
- 각 Iceberg 테이블이 현재 사용하는 `metadata.json` 위치
- principal, principal role, catalog role과 권한
- Polaris 정책과 내부 상태

PostgreSQL에는 다음 데이터가 저장되지 않습니다.

- 업로드한 JSON 원본 파일
- Iceberg Parquet 데이터 파일
- Iceberg `metadata.json`과 manifest 파일 자체

이 파일들은 MinIO의 `jsondocs` bucket에 저장됩니다. Oracle과 Trino도 Polaris용 PostgreSQL을 직접 조회하지 않습니다. Trino는 Polaris REST API로 테이블 위치와 권한을 확인한 다음 MinIO의 Iceberg 파일을 직접 읽습니다.

```text
Oracle 26ai → DG4ODBC → Trino → Polaris REST API → PostgreSQL
                              └──────────────────→ MinIO
```

따라서 PostgreSQL 장애 시 기존 MinIO 파일이 즉시 삭제되지는 않지만, Polaris가 catalog와 table pointer를 확인하거나 갱신할 수 없어 Trino의 Iceberg 작업이 실패할 수 있습니다. PostgreSQL의 `postgres-data` 볼륨은 운영 데이터로 취급하여 정기적으로 백업해야 합니다.

호스트의 hosts 파일에 다음 줄을 추가합니다.

```text
192.168.56.10 woko.labs.localhost.com
```

## 시작과 종료

Linux/WSL/Git Bash에서 실행합니다.

```sh
cp .env.example .env
sh scripts/init.sh
sh scripts/start.sh
sh scripts/stop.sh
```

모든 프로젝트 컨테이너, 볼륨, Compose 이미지까지 제거하려면 아래를 실행합니다. 업로드 파일과 Iceberg 데이터도 삭제됩니다.

```sh
sh scripts/remove-all-images.sh
```

첫 시작 시 `samples/`의 JSON 두 개가 MinIO에 복사됩니다. 앱으로 업로드한 파일만 Iceberg 메타정보 테이블에 자동 등록됩니다. 샘플도 등록하려면 앱에서 다시 업로드하면 됩니다.

## Oracle 연결 순서

전체 설치 및 구성 절차는 [Oracle Database Gateway for ODBC와 Trino 연결](docs/oracle-dg4odbc-trino-install.md)을 따릅니다.

1. Oracle Database Gateways 26ai 설치 미디어의 Oracle Universal Installer에서 **Oracle Database Gateway for ODBC**를 `/home/oracle/app/oracle/dbhome`에 설치하고 `$ORACLE_HOME/bin/dg4odbc`를 확인합니다. 기존 Database와 같은 home을 사용하려면 release가 동일한 26ai여야 합니다.
2. unixODBC와 64-bit Trino 호환 vendor ODBC driver를 설치합니다.
3. [odbcinst.ini](oracle/gateway/odbcinst.ini)의 Simba `.so` 경로와 [listener-snippet.ora](oracle/gateway/listener-snippet.ora)의 vendor library 경로를 실제 설치 위치로 변경합니다. 이를 `/etc/odbcinst.ini`로 설치하고 [odbc.ini](oracle/gateway/odbc.ini)를 `/etc/odbc.ini`로 설치합니다.
4. Oracle 계정에서 `isql -v TrinoProd jsondoc_app unused-no-auth`로 ODBC 직접 연결과 Trino SQL을 먼저 검증합니다.
5. Oracle 계정에서 `sh scripts/apply-oracle-gateway-config.sh`를 실행합니다. 스크립트는 `ORACLE_HOME=/home/oracle/app/oracle/dbhome`을 사용하며 `initTRINO.ora`, 전용 `LISTENER_TRINO:1522`, `TRINO_GATEWAY` alias를 적용합니다. 기존 Net 파일은 `.bak`으로 백업합니다.
6. `lsnrctl start LISTENER_TRINO`와 `tnsping TRINO_GATEWAY`로 Gateway listener와 alias를 확인합니다.
7. [01_trino_metadata_view.sql](oracle/sql/01_trino_metadata_view.sql)로 database link와 메타정보 뷰를 생성합니다.
8. [02_bigdata_jsondoc.sql](oracle/sql/02_bigdata_jsondoc.sql)로 샘플 JSON 외부 테이블/뷰를 생성합니다. 검색된 개별 URI는 [03_selected_object_external_table.sql](oracle/sql/03_selected_object_external_table.sql)의 `object_uri`에 넣어 사용합니다.

설치 상태는 Oracle 계정에서 다음 명령으로 점검합니다.

```sh
sh scripts/verify-oracle-gateway.sh
```

Oracle Linux 9에서는 Gateway 호스트에 unixODBC runtime이 필요합니다. `unixODBC-devel`은 드라이버를 소스 빌드할 때만 필요하며 이 구성에는 필수가 아닙니다.

```sh
sudo dnf install -y unixODBC
ls -l /usr/lib64/libodbc.so.2
odbcinst -j
```

`initTRINO.ora`의 `HS_FDS_SHAREABLE_NAME`은 runtime 패키지가 제공하는 `/usr/lib64/libodbc.so.2`를 사용합니다.

이 OL9 Gateway 환경에서는 `HS_LANGUAGE=AMERICAN_AMERICA.AL32UTF8` 사용 시 DG4ODBC의 `SQLConnectW`가 DSN 문자열을 훼손하여 `IM002`와 `ORA-28500`을 발생시켰습니다. 프로젝트의 검증된 Gateway 문자셋 설정은 다음과 같습니다.

```ini
HS_LANGUAGE=AMERICAN_AMERICA.WE8ISO8859P1
```

이 값은 영문 메타정보 조회용입니다. 한글 메타데이터의 왕복 변환은 별도의 Unicode ABI 호환성 검증이 필요합니다. 상세 trace 판별 방법은 [Oracle DG4ODBC–Trino 설치 가이드](docs/oracle-dg4odbc-trino-install.md#isql은-성공하지만-oracle에서-ora-28500이-발생하는-경우)를 참고합니다.

주의: unixODBC는 Driver Manager일 뿐 Trino ODBC 드라이버를 포함하지 않습니다. `oracle/gateway/odbcinst.ini`의 `.so` placeholder는 반드시 별도로 구입/설치한 64-bit Trino 호환 ODBC 드라이버의 실제 경로로 변경해야 합니다.

### Linux용 Trino ODBC 드라이버 설치

Trino 프로젝트는 Linux용 공식 ODBC 바이너리를 배포하지 않으므로 Simba/insightsoftware Trino ODBC 또는 Starburst V2 Linux ODBC 같은 64-bit vendor driver를 준비해야 합니다. 드라이버의 라이선스와 Community Trino 483 호환 여부를 공급사에서 확인하십시오.

Oracle Linux 9 x86_64용 RPM을 준비한 후 root 계정에서 설치합니다.

```sh
dnf install -y unixODBC
dnf install -y ./<vendor-trino-odbc-driver>.x86_64.rpm
```

설치된 패키지와 실제 공유 라이브러리 경로를 확인합니다.

```sh
rpm -qa | grep -Ei 'trino|starburst|simba|odbc'
rpm -ql <설치된-ODBC-패키지명> | grep '\.so'
find /opt /usr/local /usr/lib64 -type f \
  \( -iname '*trino*.so' -o -iname '*starburst*.so' -o -iname '*simba*.so' \) \
  2>/dev/null
```

찾은 64-bit `.so` 절대 경로를 `/etc/odbcinst.ini`에 드라이버로 등록합니다.

```ini
[Simba Trino ODBC Driver]
Description=64-bit Simba Trino ODBC Driver
Driver=/실제/simba/trino/lib/driver64.so
Setup=/실제/simba/trino/lib/driver64.so
UsageCount=1
```

`/etc/odbc.ini`에는 `TrinoProd` DSN을 등록합니다.

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

기존 unixODBC 설정을 덮어쓰지 않고 driver와 system DSN을 등록합니다.

등록 전에 두 템플릿 파일에 다음 내용이 들어 있어야 합니다. `.so` 경로는 Simba RPM에서 확인한 실제 64-bit driver 경로로 변경합니다.

`oracle/gateway/odbcinst.ini`:

```ini
[Simba Trino ODBC Driver]
Description=64-bit Simba Trino ODBC Driver
Driver=/실제/simba/trino/lib/driver64.so
Setup=/실제/simba/trino/lib/driver64.so
UsageCount=1
```

`oracle/gateway/odbc.ini`:

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

```sh
odbcinst -i -d -f oracle/gateway/odbcinst.ini
odbcinst -i -s -l -f oracle/gateway/odbc.ini
odbcinst -q -d -n 'Simba Trino ODBC Driver'
odbcinst -q -s -n TrinoProd
```

`Driver=Simba Trino ODBC Driver`는 `.so` 경로가 아니라 `odbcinst.ini`의 section 이름입니다. 상세한 항목 설명과 설치 후 검증 방법은 [Oracle DG4ODBC–Trino 설치 가이드](docs/oracle-dg4odbc-trino-install.md#oracle-gatewayodbcinstini-전체-내용)를 참고합니다.

드라이버의 의존 라이브러리가 모두 발견되는지 확인합니다. `not found`가 하나라도 있으면 해당 vendor 패키지 또는 라이브러리 경로를 먼저 보완해야 합니다.

```sh
ldd /실제/vendor/driver/lib/driver64.so
```

`listener-snippet.ora`의 `LD_LIBRARY_PATH`에도 드라이버 `.so`가 위치한 디렉터리를 반영한 다음 Oracle OS 계정으로 DSN을 직접 검증합니다.

```sh
export ORACLE_HOME=/home/oracle/app/oracle/dbhome
export ODBCINI=/etc/odbc.ini
export LD_LIBRARY_PATH=/usr/lib64:/실제/vendor/driver/lib:$ORACLE_HOME/lib

odbcinst -j
odbcinst -q -d -n 'Simba Trino ODBC Driver'
odbcinst -q -s
isql -v TrinoProd jsondoc_app unused-no-auth
```

`isql` 연결 후 아래 SQL이 성공해야 Oracle database link 구성을 진행할 수 있습니다.

```sql
SELECT count(*) FROM iceberg.jsondoc.file_metadata;
```

Oracle database link에서는 Trino의 3단계 이름 `iceberg.jsondoc.file_metadata`를 직접 사용할 수 없습니다. `odbc.ini`의 `Catalog=iceberg`가 catalog를 선택하므로 Oracle SQL에서는 `"jsondoc"."file_metadata"@trino_link`처럼 `schema.table@dblink` 형식으로 조회합니다.

`ORACLE_BIGDATA`로 HTTP/S 오브젝트를 읽으려면 Oracle 26ai 설치에 해당 드라이버와 네트워크 ACL/DBMS_CLOUD 구성이 활성화되어 있어야 합니다. 이 랩은 간단한 검증을 위해 bucket을 public-read로 만듭니다. 운영 환경에서는 public access를 끄고 HTTPS, 최소권한 계정, `DBMS_CLOUD.CREATE_CREDENTIAL`을 사용하십시오.

## 확인 명령

```sh
docker compose ps
docker compose exec trino trino --execute "SELECT * FROM iceberg.jsondoc.file_metadata"
curl http://192.168.56.10:8080/v1/info
```

## 중요한 제약

- Polaris 1.7은 `relational-jdbc` persistence로 PostgreSQL을 사용합니다. `postgres-data` 볼륨을 삭제하지 않는 한 catalog, namespace, table pointer와 RBAC 상태가 유지됩니다.
- `polaris-bootstrap`은 PostgreSQL의 `polaris_schema`와 root realm을 멱등 생성하고, `polaris-setup`은 `jsondoc_catalog`를 멱등 생성합니다.
- 이 Compose 랩은 MinIO 정적 자격증명을 Trino에 전달하며 credential vending을 끕니다. 운영에서는 TLS, 별도 principal/role, Secret 저장소와 MinIO STS 기반 credential vending을 권장합니다.
- Polaris catalog에는 `rest-metrics-reporting-enabled=false`를 설정하여 테이블 생성 직후 Iceberg REST metrics가 404 경고를 남기는 불필요한 로그를 방지합니다.
- `.env`에서 MinIO 자격증명을 바꾸면 Trino와 앱에도 Compose 환경변수로 동일하게 전달됩니다.
- Oracle external table의 `LOCATION`은 DDL이므로 일반 뷰의 행 값으로 동적으로 치환되지 않습니다. 제공한 흐름은 메타정보 뷰에서 URI 검색 후 해당 URI로 외부 테이블 DDL을 생성하는 2단계입니다.
