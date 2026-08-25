# 1. 2 VM IP 토폴로지와 네트워크

별도 hostname이나 `/etc/hosts` alias 없이 Public/Private IP를 용도별로 분리합니다.

```text
VM1 storage/catalog
  Private: 10.0.27.145
  Public : 141.148.12.16
  MinIO + PostgreSQL + Polaris

VM2 compute/app
  Private: 10.0.121.203
  Public : 129.153.132.242
  Doris FE + Doris BE + JSONDoc App

외부 Oracle 26ai
  DG4ODBC → 129.153.132.242:9030
  ORACLE_BIGDATA → 141.148.12.16:9000
```

VM 내부 통신은 `127.0.0.1`, VM1↔VM2는 Private IP, Oracle·관리자 외부 접속만 Public IP를 사용합니다. OCI Public IP는 VNIC에 직접 붙은 주소가 아닌 NAT 주소이므로 Doris `priority_networks`에는 VM2 Private IP만 사용합니다.

## 허용 흐름

| 출발지 | 목적지 | 주소/포트 | 용도 |
|---|---|---|---|
| 사용자/reverse proxy | VM2 App | `129.153.132.242:8501` | JSONDoc UI/API |
| Oracle, 관리자 | VM2 Doris FE | `129.153.132.242:9030` | MySQL/ODBC SQL |
| VM2 App | VM2 Doris FE | `127.0.0.1:9030` | metadata SQL |
| VM2 Doris FE | VM2 Doris BE | `10.0.121.203:9050` 및 내부 포트 | heartbeat/query/data |
| VM2 App, Doris BE | VM1 MinIO | `10.0.27.145:9000` | S3 object API |
| Oracle | VM1 MinIO | `141.148.12.16:9000` | ORACLE_BIGDATA HTTP |
| VM2 Doris | VM1 Polaris | `10.0.27.145:8181` | Iceberg REST/OAuth2 |
| VM1 Polaris | VM1 PostgreSQL | `127.0.0.1:5432` | relational-jdbc |
| VM1 Polaris | VM1 MinIO | `127.0.0.1:9000` | internal object access |

OCI NSG/security list와 OL9 firewalld를 모두 제한합니다.

- VM1 Public `9000`: Oracle source Public IP만 허용
- VM1 Private `9000`, `8181`: VM2 Private `10.0.121.203/32`만 허용
- VM1 `9001`, `8182`: 관리자 source IP만 허용
- VM1 `5432`: localhost only, 외부 개방 금지
- VM2 Public `9030`: Oracle과 관리자 source IP만 허용
- VM2 Public `8501`, `8030`: 승인된 사용자/관리자 source IP만 허용
- VM2 `8040`, `8050`, `8060`, `9050`, `9060`, `9010`, `9020`: Public 개방 금지

VM1의 Private endpoint 예시:

```sh
sudo firewall-cmd --permanent \
  --add-rich-rule='rule family=ipv4 source address=10.0.121.203/32 port port=9000 protocol=tcp accept'
sudo firewall-cmd --permanent \
  --add-rich-rule='rule family=ipv4 source address=10.0.121.203/32 port port=8181 protocol=tcp accept'
sudo firewall-cmd --reload
```

Public IP를 직접 사용하면 공인 CA TLS 인증서 발급과 IP 변경 대응이 제한됩니다. 이 POC는 IP 고정과 source ACL을 전제로 하며, 운영 전환 시 DNS 이름, TLS 및 load balancer를 권장합니다.
