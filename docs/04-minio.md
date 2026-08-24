# 4. VM1 MinIO

POC parity를 위해 `RELEASE.2025-07-23T15-54-02Z` x86-64 RPM을 사용합니다. 공식 MinIO 배포처에서 RPM을 내려받아 checksum/signature를 검증한 후 설치합니다.

```sh
dnf install -y ./minio-20250723155402.0.0-1.x86_64.rpm
install -d -o minio-user -g minio-user -m 0750 /var/lib/minio/data
install -m 0600 -o root -g root config/minio/minio.env.example /etc/default/minio
vi /etc/default/minio
systemctl enable --now minio
```

RPM이 만든 service의 `User`, `EnvironmentFile`, `ExecStart`가 실제 설치와 맞는지 확인합니다.

```sh
systemctl cat minio
systemctl status minio
curl -fsS http://127.0.0.1:9000/minio/health/live
```

MinIO Client를 관리 VM 또는 VM1에 설치하고 초기화합니다.

```sh
install -m 0755 mc /usr/local/bin/mc
mc alias set poc http://127.0.0.1:9000 minioadmin '<실제암호>'
mc mb --ignore-existing poc/jsondocs
```

Oracle `ORACLE_BIGDATA`의 무자격증명 HTTP POC를 위해서만 bucket 읽기를 공개합니다.

```sh
mc anonymous set download poc/jsondocs
mc anonymous get poc/jsondocs
```

운영에서는 public access를 제거하고 HTTPS 및 Oracle credential을 사용합니다.

```sh
mc anonymous set none poc/jsondocs
```

검증:

```sh
mc cp samples/customer-001.json poc/jsondocs/samples/customer-001.json
mc stat poc/jsondocs/samples/customer-001.json
curl -f http://141.148.12.16:9000/jsondocs/samples/customer-001.json
```

Doris catalog에서는 MinIO virtual-host 방식이 아니라 반드시 다음 값을 사용합니다.

```text
s3.endpoint=http://10.0.27.145:9000
use_path_style=true
```

`s3.use_path_style`이 아니라 `use_path_style`입니다. 잘못 설정하면 Doris BE가 `bucket.hostname`을 해석하다 `curlCode: 6`으로 실패합니다.
