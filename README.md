# Oracle · Doris · Polaris · Iceberg · MinIO OL9 VM POC

Docker Compose에서 검증한 JSONDoc 흐름을 컴포넌트별 Oracle Linux 9 VM으로 분리하는 설치 프로젝트입니다. Oracle Database 26ai는 기존 외부 시스템을 사용하며, 나머지 서비스는 systemd로 운영합니다.

검증에 사용한 Docker Compose 성공본은 [`docker-poc/`](docker-poc/README.md)에 함께 보관합니다. VM 전환 전 기능 재현이나 설정 비교가 필요할 때 먼저 Docker POC를 실행하십시오.

## 목표 구조

```text
사용자 → App VM → MinIO VM (JSON 원본)
             └→ Doris FE VM → Doris BE VM → MinIO VM (Iceberg Parquet/metadata)
                              └→ Polaris VM → PostgreSQL VM

Oracle 26ai → DG4ODBC → unixODBC → MariaDB Connector/ODBC → Doris FE:9030
Oracle 26ai → ORACLE_BIGDATA/HTTP → MinIO:9000
```

PostgreSQL은 Polaris의 catalog/RBAC/table pointer만 영속화합니다. JSON, Parquet, Iceberg metadata 파일은 MinIO에 저장됩니다.

## 기본 VM 인벤토리

| VM | FQDN | IP | 최소 POC 사양 | 주요 포트 |
|---|---|---:|---|---|
| Oracle DB/Gateway | `oracle.labs.localhost.com` | `192.168.56.10` | 기존 환경 | 1521, 1522 |
| App | `app.labs.localhost.com` | `192.168.56.11` | 2 vCPU, 4 GB | 8501 |
| MinIO | `minio.labs.localhost.com` | `192.168.56.12` | 4 vCPU, 8 GB, 별도 data disk | 9000, 9001 |
| PostgreSQL | `postgres.labs.localhost.com` | `192.168.56.13` | 4 vCPU, 8 GB | 5432 |
| Polaris | `polaris.labs.localhost.com` | `192.168.56.14` | 4 vCPU, 8 GB, Java 21 | 8181, 8182 |
| Doris FE | `doris-fe.labs.localhost.com` | `192.168.56.15` | 4 vCPU, 16 GB, Java 17 | 8030, 9010, 9020, 9030 |
| Doris BE | `doris-be.labs.localhost.com` | `192.168.56.16` | 8 vCPU, 16 GB, 별도 data disk | 8040, 8050, 8060, 9050, 9060 |

이는 기능 POC 최소안입니다. 운영 설계에서는 FE 3대, BE 3대 이상, PostgreSQL HA, 다중 노드 MinIO 및 TLS/LB를 별도로 설계합니다.

## 설치 순서

1. [토폴로지와 방화벽](docs/01-topology-network.md)
2. [공통 OL9 준비](docs/02-ol9-base.md)
3. [PostgreSQL 17](docs/03-postgresql.md)
4. [MinIO](docs/04-minio.md)
5. [Apache Polaris](docs/05-polaris.md)
6. [Apache Doris FE/BE](docs/06-doris.md)
7. [JSONDoc 앱](docs/07-app.md)
8. [Oracle DG4ODBC와 ORACLE_BIGDATA](docs/08-oracle.md)
9. [통합 검증과 운영](docs/09-validation-operations.md)

`inventory/hosts.example`과 `config/`의 템플릿에서 비밀번호와 설치 경로를 환경에 맞게 변경하십시오. 비밀번호 placeholder가 남아 있으면 서비스를 시작하지 마십시오.

## 고정 버전과 설치 미디어

- Oracle Linux 9.8 x86-64
- Apache Doris 4.0.1 x86-64 binary distribution
- Apache Polaris 1.7.0 binary distribution
- PostgreSQL 17
- MinIO `RELEASE.2025-07-23T15-54-02Z`
- MariaDB Connector/ODBC 3.2.8 x86-64
- Oracle Database Gateway for ODBC 26ai

인터넷에서 직접 실행 파일을 내려받아 바로 실행하지 않습니다. 공식 배포처에서 파일, `.asc`/SHA-512 또는 SHA-256을 함께 내려받아 검증한 후 내부 staging 저장소에 보관합니다.

## 성공 기준

```sql
-- Doris
SELECT COUNT(*) FROM polaris_iceberg.jsondoc.file_metadata;

-- Oracle metadata path
SELECT COUNT(*)
FROM "jsondoc_gateway"."file_metadata"@doris_link;

-- Oracle object path
SELECT document_id, document_type, customer_name
FROM customer_jsondoc_v;
```

앱에서 JSON 하나를 업로드한 후 세 경로가 동일한 문서를 가리키면 POC 완료입니다.

## 공식 참고 자료

- [Apache Doris manual deployment](https://doris.apache.org/docs/install/deploy-manually/integrated-storage-compute-deploy-manually/)
- [Apache Doris Iceberg catalog](https://doris.apache.org/docs/lakehouse/catalogs/iceberg-catalog/)
- [Apache Polaris binary distribution](https://polaris.apache.org/releases/1.7.0/binary-distribution/)
- [Apache Polaris relational JDBC persistence](https://polaris.apache.org/in-dev/unreleased/relational-jdbc-backend/)
- [MinIO Linux 설치](https://min.io/docs/minio/linux/operations/install-deploy-manage/deploy-minio-single-node-single-drive.html)
- [PostgreSQL Red Hat 계열 설치](https://www.postgresql.org/download/linux/redhat/)
- [Oracle Database Gateway for ODBC 26ai](https://docs.oracle.com/en/database/oracle/oracle-database/26/otgis/install-odbc-gateway.html)
