# 1. 토폴로지와 네트워크

## 통신 매트릭스

| Source | Destination | Port | 목적 |
|---|---|---:|---|
| 사용자/관리망 | App | 8501/TCP | JSON 업로드 UI |
| 사용자/Oracle/Doris | MinIO | 9000/TCP | S3/HTTP object API |
| 관리망 | MinIO | 9001/TCP | Console |
| App/Oracle | Doris FE | 9030/TCP | MySQL protocol |
| Doris FE | Doris BE | 9050, 9060, 8040, 8060/TCP | heartbeat/query/data |
| Doris BE | MinIO | 9000/TCP | Iceberg data write/read |
| Doris FE/BE | Polaris | 8181/TCP | Iceberg REST/OAuth2 |
| Polaris | PostgreSQL | 5432/TCP | relational-jdbc persistence |
| Oracle DB | Gateway listener | 1522/TCP | heterogeneous service |

모든 VM에서 FQDN이 동일한 사설 IP로 해석되어야 합니다. IP와 FQDN을 혼합해 Doris 노드를 등록하지 마십시오.

```sh
getent hosts minio.labs.localhost.com postgres.labs.localhost.com \
  polaris.labs.localhost.com doris-fe.labs.localhost.com doris-be.labs.localhost.com
```

각 VM에서 필요한 포트만 `firewalld`에 개방하고 source CIDR을 POC 망으로 제한합니다. 예:

```sh
firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family=ipv4 source address=192.168.56.0/24 port port=9000 protocol=tcp accept'
firewall-cmd --reload
```

인터넷 또는 사용자망에 PostgreSQL, Doris 내부 포트, Polaris management API를 직접 노출하지 않습니다. POC가 끝난 뒤 TLS를 적용하고 HTTP endpoint를 HTTPS로 교체합니다.
