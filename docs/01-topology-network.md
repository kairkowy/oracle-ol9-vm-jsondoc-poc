# 1. 2 VM 토폴로지와 네트워크

기능 POC는 저장·catalog 계층과 compute·app 계층을 각각 한 VM에 통합합니다.

```text
VM1 storage (192.168.56.11)
  MinIO + PostgreSQL + Polaris

VM2 compute (192.168.56.12)
  Doris FE + Doris BE + JSONDoc App

외부 Oracle 26ai (192.168.56.10)
  DG4ODBC → VM2:9030
  ORACLE_BIGDATA → VM1:9000
```

`inventory/hosts.example`을 Oracle과 두 VM의 `/etc/hosts`에 반영합니다. 서비스별 FQDN을 유지하되 같은 VM의 이름은 같은 IP를 가리킵니다. Doris backend는 반드시 `doris-be.labs.localhost.com` FQDN으로 등록합니다.

```sh
getent hosts storage.labs.localhost.com minio.labs.localhost.com polaris.labs.localhost.com
getent hosts compute.labs.localhost.com doris-fe.labs.localhost.com doris-be.labs.localhost.com app.labs.localhost.com
```

## 허용 흐름

| 출발지 | 목적지 | 포트 | 용도 |
|---|---|---:|---|
| 사용자/reverse proxy | VM2 App | 8501/TCP | JSONDoc UI/API |
| Oracle, 관리자 | VM2 Doris FE | 9030/TCP | MySQL/ODBC SQL |
| 관리자 | VM2 Doris FE | 8030/TCP | FE Web UI |
| VM2 App, Doris BE, Oracle | VM1 MinIO | 9000/TCP | S3/HTTP object API |
| 관리자 | VM1 MinIO | 9001/TCP | MinIO Console |
| VM2 Doris FE/BE | VM1 Polaris | 8181/TCP | Iceberg REST/OAuth2 |
| VM1 Polaris | VM1 PostgreSQL | 5432/TCP localhost | relational-jdbc |

FE/BE의 8040, 8050, 8060, 9050, 9060, 9010, 9020은 VM2 내부 통신에만 사용하고 외부에 개방하지 않습니다. PostgreSQL도 `127.0.0.1`만 listen하므로 방화벽에 5432를 열지 않습니다.

예를 들어 VM1의 MinIO API는 Oracle과 VM2만 허용합니다.

```sh
firewall-cmd --permanent \
  --add-rich-rule='rule family=ipv4 source address=192.168.56.10/32 port port=9000 protocol=tcp accept'
firewall-cmd --permanent \
  --add-rich-rule='rule family=ipv4 source address=192.168.56.12/32 port port=9000 protocol=tcp accept'
firewall-cmd --reload
```

운영 전환 시 localhost 및 내부 구간도 TLS, 최소 source ACL, secret manager를 적용합니다.
