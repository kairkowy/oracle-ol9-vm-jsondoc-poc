# 통합 검증과 운영

## 최초 통합 시험

서비스 의존 순서대로 확인합니다.

```bash
# VM1: storage/catalog 계층
sudo systemctl status postgresql-17
curl -fsS http://127.0.0.1:9000/minio/health/live
curl -fsS http://127.0.0.1:8182/q/health/ready

# VM2: compute/app 계층
sudo systemctl status doris-fe
sudo systemctl status doris-be
curl -fsS http://127.0.0.1:8501/health
curl -fsS http://10.0.121.203:9000/minio/health/live
nc -vz 10.0.121.203 8181
```

Oracle host에서는 Public endpoint를 확인합니다.

```bash
nc -vz 129.153.132.242 9030
curl -fsS http://141.148.12.16:9000/minio/health/live
```

Doris에서 backend와 catalog를 확인합니다.

```sql
SHOW BACKENDS;
SHOW CATALOGS;
SHOW DATABASES FROM polaris_iceberg;
SELECT COUNT(*) FROM polaris_iceberg.jsondoc.file_metadata;
```

`SHOW BACKENDS`의 `Alive=true`, BE/HTTP/BRPC port가 각각 9060/8040/8060이어야 합니다. 앱에서 `sample/customer-001.json`을 올린 뒤 count가 1 증가하고 MinIO에 다음 두 계열이 생겨야 합니다.

- `jsondocs/uploads/YYYY/MM/DD/...json`: 원본 JSON
- `warehouse/...`: Iceberg metadata와 Parquet data

Oracle에서 두 경로를 검증합니다.

```sql
SELECT object_key, object_uri, document_id
FROM jsondoc_file_metadata_v;

SELECT document_id, document_type, customer_name
FROM customer_jsondoc_v;
```

## 시작/중지 순서

시작은 VM1에서 `PostgreSQL → MinIO → Polaris`, 그 다음 VM2에서 `Doris FE → Doris BE → App` 순서입니다. 중지는 역순입니다. Oracle은 외부 기존 DB이므로 별도 운영 절차를 따릅니다. systemd unit의 `After/Wants`는 같은 VM 내부 순서만 보조하며, VM2 시작 전 VM1 health를 별도로 확인합니다.

## 백업 범위

- PostgreSQL: Polaris catalog/RBAC/pointer DB의 정기 logical/physical backup
- MinIO: `jsondocs`와 warehouse bucket 전체의 versioning, replication, object-lock 정책 검토
- Doris FE: `meta_dir` snapshot과 FE quorum 운영 시 공식 backup 절차
- 구성/비밀: `/etc/*` 파일은 secret manager/구성 저장소로 관리하고 Git에 실제 비밀번호 금지

PostgreSQL만 복구하거나 MinIO만 복구하면 catalog pointer와 Iceberg metadata가 어긋날 수 있습니다. 동일 복구 시점과 복구 순서를 운영 runbook에 정의합니다.

## POC에서 운영형으로 확대

| 계층 | POC | 운영 권고 출발점 |
|---|---|---|
| VM2 Doris | FE 1 + BE 1 + App 1 | FE 3 + BE 3 이상, App 2+, FQDN 등록, rack 분산 |
| Polaris | 1 node | 2+ node, LB, 외부 secret manager |
| VM1 PostgreSQL | 1 node | HA/backup/PITR 및 MinIO와 장애 도메인 분리 |
| VM1 MinIO | 1 node/1 disk | distributed erasure coding, 별도 장애 도메인 |
| Oracle Gateway | DB host 1개 | 별도 Gateway home/host 검토, 이중화와 접속 timeout |

운영 전에는 모든 HTTP 구간을 TLS로 바꾸고 방화벽 source를 실제 호출 VM으로 제한하며 root/minioadmin/Polaris bootstrap 자격증명을 교체합니다.

## 로그 위치

- App: `journalctl -u jsondoc-app`
- MinIO: `journalctl -u minio`
- Polaris: `journalctl -u polaris`
- Doris: `/var/log/doris/fe`, `/var/log/doris/be`와 journal
- PostgreSQL: `/var/lib/pgsql/17/data/log`
- Oracle Gateway: `$ORACLE_HOME/hs/log/DORIS_agt_*.trc`, listener log
